//
//  Router.swift
//  Jared
//
//  Created by Zeke Snider on 4/20/20.
//  Copyright © 2020 Zeke Snider. All rights reserved.
//

import Foundation
import JaredFramework

class Router : RouterDelegate {
    var pluginManager: RouteProvider
    var messageDelegates: [MessageDelegate]
    private let matcher = MessageMatcher()
    private let filterPolicy: InboundFilterPolicy

    init(pluginManager: RouteProvider, messageDelegates: [MessageDelegate],
         flags: RuntimeFlags = UserDefaultsRuntimeFlags()) {
        self.pluginManager = pluginManager
        self.messageDelegates = messageDelegates
        self.filterPolicy = InboundFilterPolicy(flags: flags)
    }

    func route(message myMessage: Message) {
        // Stage 1 — NotifyDelegates: every message (incl. outgoing) reaches delegates.
        messageDelegates.forEach { delegate in delegate.didProcess(message: myMessage) }

        // Stage 2 — FilterPolicy: self-message, body-type, global-disabled + /enable bypass.
        guard filterPolicy.shouldRoute(myMessage) else { return }

        // Stage 3/4 — MatchRoutes + InvokeRoute.
        for route in pluginManager.getAllRoutes() {
            guard pluginManager.enabled(routeName: route.name) else { continue }
            if let deliverable = matcher.matchingMessage(route: route, message: myMessage) {
                route.call(deliverable)
            }
        }
    }
}
