//
//  Configuration.swift
//  Jared
//
//  Created by Zeke Snider on 8/17/20.
//  Copyright © 2020 Zeke Snider. All rights reserved.
//

import Foundation

struct ConfigurationFile: Decodable {
    let disabledCommands: [String: Bool]
    let webhooks: [RichWebhook]
    let webServer: WebserverConfiguration

    init(disabledCommands: [String: Bool] = [:],
         webhooks: [RichWebhook] = [],
         webServer: WebserverConfiguration = WebserverConfiguration(port: 3000)) {
        self.disabledCommands = disabledCommands
        self.webhooks = webhooks
        self.webServer = webServer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Accept new "disabledCommands" key; fall back to legacy "routes" map for existing configs.
        if let newMap = try? c.decodeIfPresent([String: Bool].self, forKey: .disabledCommands) {
            disabledCommands = newMap
        } else if let legacyRoutes = try? c.decodeIfPresent([String: LegacyRouteConfiguration].self, forKey: .routes) {
            disabledCommands = legacyRoutes.mapValues { $0.disabled }
        } else {
            disabledCommands = [:]
        }
        webhooks  = (try? c.decodeIfPresent([RichWebhook].self,            forKey: .webhooks)) ?? []
        webServer = (try? c.decodeIfPresent(WebserverConfiguration.self,   forKey: .webServer)) ?? WebserverConfiguration(port: 3000)
    }

    private enum CodingKeys: String, CodingKey {
        case disabledCommands, routes, webhooks, webServer
    }
}

private struct LegacyRouteConfiguration: Decodable {
    let disabled: Bool
}

struct WebserverConfiguration: Decodable {
    let port: Int
    let bearerToken: String?
    let tunnel: TunnelConfiguration?

    init(port: Int, bearerToken: String? = nil, tunnel: TunnelConfiguration? = nil) {
        self.port = port
        self.bearerToken = bearerToken
        self.tunnel = tunnel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        port = try container.decode(Int.self, forKey: .port)
        bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken)
        tunnel = try container.decodeIfPresent(TunnelConfiguration.self, forKey: .tunnel)
    }

    private enum CodingKeys: String, CodingKey {
        case port, bearerToken, tunnel
    }
}

