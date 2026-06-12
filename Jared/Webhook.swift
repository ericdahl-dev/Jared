//
//  Webhook.swift
//  Jared
//
//  Created by Zeke Snider on 8/16/20.
//  Copyright © 2020 Zeke Snider. All rights reserved.
//

import Foundation
import JaredFramework

// MARK: - Webhook mode

enum WebhookMode: String, Codable {
    case notify  // retries OK; response body ignored
    case command // NO retry (enforced); response body sent as iMessage reply
}

// MARK: - Policy types

struct WebhookAuth: Codable {
    var secret: String?
}

struct DeliveryPolicy: Codable {
    var timeoutSeconds: Double?
}

struct FailurePolicy: Codable {
    var maxRetries: Int?
}

// MARK: - RichWebhook

struct RichWebhook: Decodable {
    var url: String
    var isEnabled: Bool
    var mode: WebhookMode
    var routes: [Route]?
    var auth: WebhookAuth?
    var deliveryPolicy: DeliveryPolicy
    var failurePolicy: FailurePolicy

    // mode=command always enforces 0 retries to prevent duplicate iMessage replies (D17)
    var effectiveMaxRetries: Int {
        mode == .command ? 0 : (failurePolicy.maxRetries ?? 3)
    }

    var effectiveTimeout: Double {
        deliveryPolicy.timeoutSeconds ?? 10.0
    }

    // Backward-compatible decoder: handles both old {url, routes} and new full format
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        mode = (try? c.decodeIfPresent(WebhookMode.self, forKey: .mode)) ?? .notify
        routes = try? c.decodeIfPresent([Route].self, forKey: .routes)
        auth = try? c.decodeIfPresent(WebhookAuth.self, forKey: .auth)
        deliveryPolicy = (try? c.decodeIfPresent(DeliveryPolicy.self, forKey: .deliveryPolicy)) ?? DeliveryPolicy()
        failurePolicy = (try? c.decodeIfPresent(FailurePolicy.self, forKey: .failurePolicy)) ?? FailurePolicy()
    }

    init(url: String, isEnabled: Bool = true, mode: WebhookMode = .notify, routes: [Route]? = nil,
         auth: WebhookAuth? = nil, deliveryPolicy: DeliveryPolicy = DeliveryPolicy(),
         failurePolicy: FailurePolicy = FailurePolicy()) {
        self.url = url
        self.isEnabled = isEnabled
        self.mode = mode
        self.routes = routes
        self.auth = auth
        self.deliveryPolicy = deliveryPolicy
        self.failurePolicy = failurePolicy
    }

    private enum CodingKeys: String, CodingKey {
        case url, isEnabled = "enabled", mode, routes, auth, deliveryPolicy, failurePolicy
    }
}

// MARK: - Response

struct WebhookResponse: Decodable {
    var success: Bool
    var body: TextBody?
    var error: String?
}
