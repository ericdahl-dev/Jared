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
    let webhooks: [Webhook]
    let webServer: WebserverConfiguration
    let llm: LLMConfiguration?

    init(routes: [String: RouteConfiguration] = [:],
         webhooks: [Webhook] = [],
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
        webhooks  = (try? c.decodeIfPresent([Webhook].self,                    forKey: .webhooks)) ?? []
        webServer = (try? c.decodeIfPresent(WebserverConfiguration.self,       forKey: .webServer)) ?? WebserverConfiguration(port: 3000)
        llm       = try? c.decodeIfPresent(LLMConfiguration.self,              forKey: .llm)
    }

    private enum CodingKeys: String, CodingKey {
        case routes, webhooks, webServer, llm
    }
}

struct WebserverConfiguration: Decodable {
    let port: Int
}

struct RouteConfiguration: Decodable {
    let disabled: Bool
}
