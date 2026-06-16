//
//  WebHookManager.swift
//  Jared
//
//  Created by Zeke Snider on 2/2/19.
//  Copyright © 2019 Zeke Snider. All rights reserved.
//

import Foundation
import JaredFramework
import os
import CryptoKit

private let logger = Logger(subsystem: "com.zekesnider.jared", category: "webhooks")

class WebHookManager: MessageDelegate, RoutingModule {
    var urlSession: URLSession
    var webhooks = [RichWebhook]()
    var routes = [Route]()
    var sender: MessageSender
    var keychain: KeychainAccessor
    var description = "Routes provided by webhooks"
    /// Base nanosecond unit for retry backoff (2^attempt × base). Override in tests for speed.
    var retryDelayBase: UInt64 = 1_000_000_000

    /// On-disk delivery log (newest first, capped). Survives app restarts so the
    /// management UI can show history across launches.
    let deliveryStore: WebhookDeliveryStore

    /// Snapshot of persisted deliveries, newest first. Re-read from disk on access
    /// so callers see records written by deliveries that happened in this session.
    var deliveryLog: [WebhookDeliveryRecord] { deliveryStore.load() }

    private func record(_ webhookURL: String, deliveryId: String, attempt: Int,
                        statusCode: Int? = nil, error: String? = nil) {
        let rec = WebhookDeliveryRecord(deliveryId: deliveryId, webhookURL: webhookURL,
                                        date: Date(), statusCode: statusCode,
                                        errorDescription: error, attempt: attempt)
        deliveryStore.append(rec)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .webhookDelivered, object: self,
                                            userInfo: ["url": webhookURL])
        }
    }

    public init(webhooks: [RichWebhook]?, session: URLSessionConfiguration = .ephemeral,
                sender: MessageSender, keychain: KeychainAccessor = KeychainStore(),
                deliveryStore: WebhookDeliveryStore = WebHookManager.defaultDeliveryStore()) {
        session.timeoutIntervalForResource = 10.0
        self.sender = sender
        self.keychain = keychain
        self.deliveryStore = deliveryStore
        urlSession = URLSession(configuration: session)
        updateHooks(to: webhooks)
    }

    required convenience init(sender: MessageSender) {
        self.init(webhooks: nil, sender: sender)
    }

    static func defaultDeliveryStore() -> WebhookDeliveryStore {
        let url = ConfigurationHelper.getSupportDirectory()
            .appendingPathComponent("webhook-deliveries.json")
        return WebhookDeliveryStore(fileURL: url)
    }

    // MARK: - MessageDelegate

    public func didProcess(message: Message) {
        let globalWebhooks = webhooks.filter { ($0.routes ?? []).isEmpty }
        guard !globalWebhooks.isEmpty else { return }
        Task {
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for webhook in globalWebhooks {
                    if inFlight >= 5 {
                        await group.next()
                        inFlight -= 1
                    }
                    let w = webhook
                    group.addTask { await self.deliverWebhook(w, message: message) }
                    inFlight += 1
                }
            }
        }
    }

    // MARK: - Delivery

    func deliverWebhook(_ webhook: RichWebhook, message: Message) async {
        guard let parsedUrl = URL(string: webhook.url) else {
            logger.error("Webhook \(webhook.url, privacy: .public): invalid URL — skipping delivery")
            return
        }

        guard let webhookBody = WebHookManager.createWebhookBody(message) else {
            logger.error("Webhook \(webhook.url, privacy: .public): failed to encode message body")
            return
        }

        let deliveryId = UUID().uuidString
        let maxRetries = webhook.effectiveMaxRetries

        for attempt in 0...maxRetries {
            var request = WebHookManager.makeDeliveryRequest(
                url: parsedUrl,
                webhook: webhook,
                body: webhookBody,
                deliveryId: deliveryId,
                keychain: keychain
            )

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return }

                if (400...499).contains(httpResponse.statusCode) {
                    logger.warning("Webhook \(webhook.url, privacy: .public): 4xx \(httpResponse.statusCode, privacy: .public) — not retrying")
                    record(webhook.url, deliveryId: deliveryId, attempt: attempt + 1, statusCode: httpResponse.statusCode)
                    return
                }

                if (200...299).contains(httpResponse.statusCode) {
                    logger.notice("Webhook \(webhook.url, privacy: .public): delivered (attempt \(attempt + 1, privacy: .public), status \(httpResponse.statusCode, privacy: .public))")
                    record(webhook.url, deliveryId: deliveryId, attempt: attempt + 1, statusCode: httpResponse.statusCode)
                    if webhook.mode == .command {
                        guard let decoded = try? JSONDecoder().decode(WebhookResponse.self, from: data) else {
                            logger.warning("Webhook \(webhook.url, privacy: .public): unable to parse command response")
                            return
                        }
                        if decoded.success, let replyText = decoded.body?.message {
                            sender.send(replyText, to: message.RespondTo())
                        } else if let decodedError = decoded.error {
                            logger.warning("Webhook \(webhook.url, privacy: .public): error response: \(decodedError, privacy: .public)")
                        }
                    }
                    return
                }

                logger.warning("Webhook \(webhook.url, privacy: .public): status \(httpResponse.statusCode, privacy: .public) on attempt \(attempt + 1, privacy: .public)")
            } catch {
                logger.error("Webhook \(webhook.url, privacy: .public): request failed on attempt \(attempt + 1, privacy: .public): \(error.localizedDescription, privacy: .public)")
                record(webhook.url, deliveryId: deliveryId, attempt: attempt + 1, error: error.localizedDescription)
            }

            if attempt < maxRetries {
                let backoffNs = UInt64(pow(2.0, Double(attempt))) * retryDelayBase
                try? await Task.sleep(nanoseconds: backoffNs)
            }
        }

        logger.error("Webhook \(webhook.url, privacy: .public): all \(maxRetries + 1, privacy: .public) attempt(s) exhausted")
    }

    // MARK: - Configuration

    public func updateHooks(to hooks: [RichWebhook]?) {
        self.webhooks = (hooks ?? []).filter { $0.isEnabled }.map { hook in
            var newHook = hook
            // Persist inline auth.secret to Keychain on first load
            if let inlineSecret = newHook.auth?.secret {
                keychain.save(secret: inlineSecret, for: newHook.url)
            }
            // Signing is keyed by Keychain; keep auth enabled when a secret exists
            if newHook.auth == nil, keychain.secret(for: newHook.url) != nil {
                newHook.auth = WebhookAuth(secret: nil)
            }
            newHook.routes = (newHook.routes ?? []).map { route in
                var newRoute = route
                newRoute.call = { [weak self] msg in
                    Task { await self?.deliverWebhook(newHook, message: msg) }
                }
                return newRoute
            }
            return newHook
        }
        self.routes = self.webhooks.flatMap { $0.routes ?? [] }
        UserDefaults.standard.set(self.webhooks.count, forKey: JaredConstants.webhookCount)
        logger.notice("Webhooks updated: \(self.webhooks.map { $0.url }.joined(separator: ", "), privacy: .public)")
    }

    static func createWebhookBody(_ message: Message) -> Data? {
        try? JSONEncoder().encode(message)
    }

    /// Test payload uses the same Message JSON shape as production, plus `_jared_test: true`.
    static func createTestWebhookBody() -> Data? {
        let message = Message(
            body: TextBody("/test"),
            date: Date(),
            sender: Person(givenName: "Test", handle: "test@example.com", isMe: false),
            recipient: Person(givenName: "Test", handle: "test@example.com", isMe: true)
        )
        guard let base = createWebhookBody(message),
              var object = try? JSONSerialization.jsonObject(with: base) as? [String: Any] else {
            return nil
        }
        object["_jared_test"] = true
        return try? JSONSerialization.data(withJSONObject: object)
    }

    static func richWebhook(from dictionary: [String: Any]) -> RichWebhook? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else { return nil }
        return try? JSONDecoder().decode(RichWebhook.self, from: data)
    }

    /// Resolves signing from config `auth` or an existing Keychain secret.
    static func richWebhookForDelivery(from dictionary: [String: Any], keychain: KeychainAccessor) -> RichWebhook? {
        guard var webhook = richWebhook(from: dictionary) else { return nil }
        if webhook.auth == nil, keychain.secret(for: webhook.url) != nil {
            webhook.auth = WebhookAuth(secret: nil)
        }
        return webhook
    }

    static func makeDeliveryRequest(
        url: URL,
        webhook: RichWebhook,
        body: Data,
        deliveryId: String,
        keychain: KeychainAccessor
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue(deliveryId, forHTTPHeaderField: "X-Jared-Delivery-Id")
        request.addValue(webhook.url, forHTTPHeaderField: "X-Jared-Webhook-Id")
        request.timeoutInterval = webhook.effectiveTimeout

        if webhook.auth != nil {
            if let secret = keychain.secret(for: webhook.url) {
                let key = SymmetricKey(data: Data(secret.utf8))
                let sig = HMAC<SHA256>.authenticationCode(for: body, using: key)
                let hexSig = sig.map { String(format: "%02x", $0) }.joined()
                request.addValue("sha256=\(hexSig)", forHTTPHeaderField: "X-Jared-Signature")
            } else {
                logger.warning("Webhook \(webhook.url, privacy: .public): auth configured but no Keychain secret found — delivering unsigned")
            }
        }

        return request
    }
}
