//
//  WebHookManager.swift
//  Jared
//
//  Created by Zeke Snider on 2/2/19.
//  Copyright © 2019 Zeke Snider. All rights reserved.
//

import Foundation
import JaredFramework

class WebHookManager: MessageDelegate, RoutingModule {
    var urlSession: URLSession
    var webhooks = [RichWebhook]()
    var routes = [Route]()
    var sender: MessageSender
    var description = "Routes provided by webhooks"

    public init(webhooks: [RichWebhook]?, session: URLSessionConfiguration = .ephemeral, sender: MessageSender) {
        session.timeoutIntervalForResource = 10.0
        self.sender = sender
        urlSession = URLSession(configuration: session)
        updateHooks(to: webhooks)
    }

    required convenience init(sender: MessageSender) {
        self.init(webhooks: nil, sender: sender)
    }

    // MARK: - MessageDelegate

    public func didProcess(message: Message) {
        for webhook in webhooks {
            // Route-based webhooks fire via Route.call callbacks set up in updateHooks
            guard (webhook.routes ?? []).isEmpty else {
                continue
            }
            Task { await self.deliverWebhook(webhook, message: message) }
        }
    }

    // MARK: - Delivery

    func deliverWebhook(_ webhook: RichWebhook, message: Message) async {
        guard let parsedUrl = URL(string: webhook.url) else {
            print("[ERROR] Webhook \(webhook.url): invalid URL — skipping delivery")
            return
        }

        guard let webhookBody = WebHookManager.createWebhookBody(message) else {
            print("[ERROR] Webhook \(webhook.url): failed to encode message body")
            return
        }

        var request = URLRequest(url: parsedUrl)
        request.httpMethod = "POST"
        request.httpBody = webhookBody
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = webhook.effectiveTimeout

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            guard (200...299).contains(httpResponse.statusCode) else {
                print("[WARN] Webhook \(webhook.url): unexpected status \(httpResponse.statusCode)")
                return
            }

            if webhook.mode == .command {
                guard let decoded = try? JSONDecoder().decode(WebhookResponse.self, from: data) else {
                    print("[WARN] Webhook \(webhook.url): unable to parse command response")
                    return
                }
                if decoded.success, let replyText = decoded.body?.message {
                    sender.send(replyText, to: message.RespondTo())
                } else if let decodedError = decoded.error {
                    print("[WARN] Webhook \(webhook.url): error response: \(decodedError)")
                }
            }
        } catch {
            print("[ERROR] Webhook \(webhook.url): request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Configuration

    public func updateHooks(to hooks: [RichWebhook]?) {
        self.webhooks = (hooks ?? []).map { hook in
            var newHook = hook
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
        print("[INFO] Webhooks updated to: \(self.webhooks.map { $0.url }.joined(separator: ", "))")
    }

    private static func createWebhookBody(_ message: Message) -> Data? {
        return try? JSONEncoder().encode(message)
    }
}
