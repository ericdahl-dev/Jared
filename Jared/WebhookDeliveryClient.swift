//
//  WebhookDeliveryClient.swift
//  Jared
//

import Foundation
import JaredFramework
import os
import CryptoKit

private let logger = Logger(subsystem: "com.zekesnider.jared", category: "webhooks")

class WebhookDeliveryClient {
    var urlSession: URLSession
    let keychain: KeychainAccessor
    /// Nil in contexts that don't handle iMessage replies (e.g. management UI test sends).
    let sender: MessageSender?
    let deliveryStore: WebhookDeliveryStore
    /// Base nanosecond unit for retry backoff (2^attempt × base). Override in tests for speed.
    var retryDelayBase: UInt64 = 1_000_000_000

    init(session: URLSessionConfiguration = .ephemeral,
         keychain: KeychainAccessor,
         sender: MessageSender? = nil,
         deliveryStore: WebhookDeliveryStore) {
        session.timeoutIntervalForResource = 10.0
        self.keychain = keychain
        self.sender = sender
        self.deliveryStore = deliveryStore
        urlSession = URLSession(configuration: session)
    }

    // MARK: - Delivery

    func deliver(_ webhook: RichWebhook, message: Message) async {
        guard let body = Self.createWebhookBody(message) else {
            logger.error("Webhook \(webhook.url, privacy: .public): failed to encode message body")
            return
        }
        await deliverCore(body: body, webhook: webhook, replyTo: message.RespondTo())
    }

    /// Single-shot delivery for test payloads: same signing/retry/recording path, no iMessage reply.
    func deliverTestBody(_ body: Data, to webhook: RichWebhook) async {
        await deliverCore(body: body, webhook: webhook, replyTo: nil as RecipientEntity?)
    }

    private func deliverCore(body: Data, webhook: RichWebhook, replyTo: RecipientEntity?) async {
        guard let parsedUrl = URL(string: webhook.url) else {
            logger.error("Webhook \(webhook.url, privacy: .public): invalid URL — skipping delivery")
            return
        }

        let deliveryId = UUID().uuidString
        let maxRetries = webhook.effectiveMaxRetries

        for attempt in 0...maxRetries {
            let request = Self.makeDeliveryRequest(
                url: parsedUrl,
                webhook: webhook,
                body: body,
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
                    if webhook.mode == .command, let replyTo, let sender {
                        guard let decoded = try? JSONDecoder().decode(WebhookResponse.self, from: data) else {
                            logger.warning("Webhook \(webhook.url, privacy: .public): unable to parse command response")
                            return
                        }
                        if decoded.success, let replyText = decoded.body?.message {
                            sender.send(replyText, to: replyTo)
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

    // MARK: - Static helpers

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
              var json = String(data: base, encoding: .utf8),
              json.hasSuffix("}") else {
            return nil
        }
        // Append without JSONSerialization round-trip so key order matches JSONEncoder output.
        json.removeLast()
        json += ",\"_jared_test\":true}"
        return json.data(using: .utf8)
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
}
