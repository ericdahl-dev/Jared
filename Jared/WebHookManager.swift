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

private let logger = Logger(subsystem: "com.zekesnider.jared", category: "webhooks")

class WebHookManager: MessageDelegate, RoutingModule {
    var webhooks = [RichWebhook]()
    var routes = [Route]()
    var sender: MessageSender
    var description = "Routes provided by webhooks"

    let deliveryStore: WebhookDeliveryStore
    var deliveryLog: [WebhookDeliveryRecord] { deliveryStore.load() }

    var client: WebhookDeliveryClient
    private var routeFactory: WebhookRouteFactory

    var retryDelayBase: UInt64 {
        get { client.retryDelayBase }
        set { client.retryDelayBase = newValue }
    }

    public init(webhooks: [RichWebhook]?, session: URLSessionConfiguration = .ephemeral,
                sender: MessageSender, keychain: KeychainAccessor = KeychainStore(),
                deliveryStore: WebhookDeliveryStore = WebHookManager.defaultDeliveryStore()) {
        self.sender = sender
        self.deliveryStore = deliveryStore
        self.client = WebhookDeliveryClient(session: session, keychain: keychain,
                                            sender: sender, deliveryStore: deliveryStore)
        self.routeFactory = WebhookRouteFactory(client: self.client)
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
                    group.addTask { await self.client.deliver(w, message: message) }
                    inFlight += 1
                }
            }
        }
    }

    // MARK: - Configuration

    public func updateHooks(to hooks: [RichWebhook]?) {
        self.webhooks = (hooks ?? []).filter { $0.isEnabled }.map { hook in
            var newHook = hook
            // Persist inline auth.secret to Keychain on first load
            if let inlineSecret = newHook.auth?.secret {
                client.keychain.save(secret: inlineSecret, for: newHook.url)
            }
            // Signing is keyed by Keychain; keep auth enabled when a secret exists
            if newHook.auth == nil, client.keychain.secret(for: newHook.url) != nil {
                newHook.auth = WebhookAuth(secret: nil)
            }
            newHook.routes = routeFactory.routes(from: newHook)
            return newHook
        }
        self.routes = self.webhooks.flatMap { $0.routes ?? [] }
        UserDefaults.standard.set(self.webhooks.count, forKey: JaredConstants.webhookCount)
        logger.notice("Webhooks updated: \(self.webhooks.map { $0.url }.joined(separator: ", "), privacy: .public)")
    }
}
