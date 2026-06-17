//
//  PluginManager.swift
//  Jared
//
//  Created by Zeke Snider on 4/9/16.
//  Copyright © 2016 Zeke Snider. All rights reserved.
//

import Foundation
import JaredFramework

class PluginManager: RouteProvider, PluginController, ConfigurationApplier {
    private var modules: [RoutingModule] = []
    var disabled = false
    var config: ConfigurationFile
    var webhooks: [String]?
    var webHookManager: WebHookManager
    var sender: MessageSender
    public var router: Router!
    private var configWatcher: ConfigurationWatcher?

    init(sender: MessageSender, configuration: ConfigurationFile) {
        self.sender = sender
        self.config = configuration

        webHookManager = WebHookManager(webhooks: configuration.webhooks, sender: sender)
        router = Router(pluginManager: self, messageDelegates: [webHookManager])

        addInternalModules()
    }

    func startWatchingConfig(at url: URL) {
        configWatcher = ConfigurationWatcher(configURL: url, applier: self) { }
        configWatcher?.start()
    }

    func apply(_ newConfig: ConfigurationFile) {
        let oldPort = config.webServer.port
        config = newConfig
        webHookManager.updateHooks(to: newConfig.webhooks)
        if newConfig.webServer.port != oldPort {
            NSLog("Config hot-reload: port changed to %d — restart required for port rebind", newConfig.webServer.port)
        }
        NSLog("Config hot-reload: configuration reloaded")
    }

    private func addInternalModules() {
        modules.append(CoreModule(sender: sender))
        modules.append(ScheduleModule(sender: sender))
        modules.append(InternalModule(sender: sender, pluginManager: self))
        modules.append(webHookManager)
    }
    
    func reload() {
        modules.removeAll()
        addInternalModules()
    }
    
    func enabled(routeName: String) -> Bool {
        if let routeConfig = config.routes[routeName.lowercased()] {
            return !routeConfig.disabled
        } else {
            return true
        }
    }
    
    func getAllModules() -> [RoutingModule] {
        return modules
    }
    
    func getAllRoutes() -> [Route] {
        return modules.flatMap { module in module.routes }
    }
}
