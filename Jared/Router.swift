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
    var pluginManager: PluginManagerDelegate
    var messageDelegates: [MessageDelegate]
    private let matcher = MessageMatcher()
    
    init(pluginManager: PluginManagerDelegate, messageDelegates: [MessageDelegate]) {
        self.pluginManager = pluginManager
        self.messageDelegates = messageDelegates
    }
    
    func route(message myMessage: Message) {
        messageDelegates.forEach { delegate in delegate.didProcess(message: myMessage) }
        
        guard myMessage.body is TextBody || myMessage.action != nil else { return }
        
        let defaults = UserDefaults.standard
        let isDisabled = defaults.bool(forKey: JaredConstants.jaredIsDisabled)
        let isEnable = (myMessage.body as? TextBody)?.message.lowercased() == "/enable"
        guard !isDisabled || isEnable else { return }
        
        for route in pluginManager.getAllRoutes() {
            guard pluginManager.enabled(routeName: route.name) else { continue }
            if let deliverable = matcher.matchingMessage(route: route, message: myMessage) {
                route.call(deliverable)
            }
        }
    }
}
