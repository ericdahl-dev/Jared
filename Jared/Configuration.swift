//
//  Configuration.swift
//  Jared
//
//  Created by Zeke Snider on 8/17/20.
//  Copyright © 2020 Zeke Snider. All rights reserved.
//

import Foundation

struct ConfigurationFile: Decodable {
    let routes: [String: RouteConfiguration]
    let webhooks: [RichWebhook]
    let webServer: WebserverConfiguration
    let llm: LLMConfiguration?

    init(routes: [String: RouteConfiguration] = [:],
         webhooks: [RichWebhook] = [],
         webServer: WebserverConfiguration = WebserverConfiguration(port: 3000),
         llm: LLMConfiguration? = nil) {
        self.routes = routes
        self.webhooks = webhooks
        self.webServer = webServer
        self.llm = llm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routes    = (try? c.decodeIfPresent([String: RouteConfiguration].self, forKey: .routes))   ?? [:]
        webhooks  = (try? c.decodeIfPresent([RichWebhook].self,                    forKey: .webhooks)) ?? []
        webServer = (try? c.decodeIfPresent(WebserverConfiguration.self,       forKey: .webServer)) ?? WebserverConfiguration(port: 3000)
        llm       = try? c.decodeIfPresent(LLMConfiguration.self,              forKey: .llm)
    }

    private enum CodingKeys: String, CodingKey {
        case routes, webhooks, webServer, llm
    }
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

struct RouteConfiguration: Decodable {
    let disabled: Bool
}
