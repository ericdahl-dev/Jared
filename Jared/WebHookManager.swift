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

    public init(webhooks: [RichWebhook]?, session: URLSessionConfiguration = .ephemeral,
                sender: MessageSender, keychain: KeychainAccessor = KeychainStore()) {
        session.timeoutIntervalForResource = 10.0
        self.sender = sender
        self.keychain = keychain
        urlSession = URLSession(configuration: session)
        updateHooks(to: webhooks)
    }

    required convenience init(sender: MessageSender) {
        self.init(webhooks: nil, sender: sender)
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
            var request = URLRequest(url: parsedUrl)
            request.httpMethod = "POST"
            request.httpBody = webhookBody
            request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.addValue(deliveryId, forHTTPHeaderField: "X-Jared-Delivery-Id")
            request.addValue(webhook.url, forHTTPHeaderField: "X-Jared-Webhook-Id")
            request.timeoutInterval = webhook.effectiveTimeout

            if webhook.auth != nil {
                if let secret = keychain.secret(for: webhook.url) {
                    let key = SymmetricKey(data: Data(secret.utf8))
                    let sig = HMAC<SHA256>.authenticationCode(for: webhookBody, using: key)
                    let hexSig = sig.map { String(format: "%02x", $0) }.joined()
                    request.addValue("sha256=\(hexSig)", forHTTPHeaderField: "X-Jared-Signature")
                } else {
                    logger.warning("Webhook \(webhook.url, privacy: .public): auth configured but no Keychain secret found — delivering unsigned")
                }
            }

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return }

                if (400...499).contains(httpResponse.statusCode) {
                    logger.warning("Webhook \(webhook.url, privacy: .public): 4xx \(httpResponse.statusCode, privacy: .public) — not retrying")
                    return
                }

                if (200...299).contains(httpResponse.statusCode) {
                    logger.notice("Webhook \(webhook.url, privacy: .public): delivered (attempt \(attempt + 1, privacy: .public), status \(httpResponse.statusCode, privacy: .public))")
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
        self.webhooks = (hooks ?? []).map { hook in
            var newHook = hook
            // Persist inline auth.secret to Keychain on first load
            if let inlineSecret = newHook.auth?.secret {
                keychain.save(secret: inlineSecret, for: newHook.url)
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
        logger.notice("Webhooks updated: \(self.webhooks.map { $0.url }.joined(separator: ", "), privacy: .public)")
    }

    private static func createWebhookBody(_ message: Message) -> Data? {
        return try? JSONEncoder().encode(message)
    }
}
