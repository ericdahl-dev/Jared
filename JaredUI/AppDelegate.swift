//
//  AppDelegate.swift
//  JaredUI
//
//  Created by Zeke Snider on 4/5/16.
//  Copyright © 2016 Zeke Snider. All rights reserved.
//

import Cocoa
import Contacts

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var sender: Jared
    var pluginManager: PluginManager
    var server: JaredWebServer
    var tunnelManager: TunnelManager
    var databaseHelper: DatabaseHandler!
    var menuBarManager: MenuBarManager!
    override init() {
        UserDefaults.standard.register(defaults: [
            JaredConstants.jaredIsDisabled: false,
            JaredConstants.restApiIsDisabled: true,
            JaredConstants.contactsAccess: CNAuthorizationStatus.notDetermined.rawValue,
            JaredConstants.fullDiskAccess: true,
            JaredConstants.preventSystemSleep: false
        ])
        
        let config = ConfigurationHelper.getConfiguration()
        
        sender = Jared()
        pluginManager = PluginManager(sender: sender, configuration: config, pluginDir: ConfigurationHelper.getPluginDirectory())
        let webServer = JaredWebServer(sender: sender, configuration: config.webServer)
        server = webServer
        let configuredPort = config.webServer.port
        tunnelManager = TunnelManager(
            configuration: config.webServer.tunnel ?? TunnelConfiguration(),
            localPortProvider: {
                webServer.isRunning ? webServer.listeningPort : configuredPort
            }
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if (ProcessInfo().arguments[safe: 1] == "-UITesting") {
            setStateForUITesting()
        }

        let messageDatabaseURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Messages").appendingPathComponent("chat.db")
        let viewController = NSApplication.shared.keyWindow?.contentViewController as? ViewController
		databaseHelper = DatabaseHandler(router: pluginManager.router, databaseLocation: messageDatabaseURL, diskAccessDelegate: viewController)
		menuBarManager = MenuBarManager(pluginManager: pluginManager)
        tunnelManager.startObserving()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tunnelConfigDidChange(_:)),
            name: TunnelManager.configurationDidChangeNotification,
            object: nil
        )

		let configURL = ConfigurationHelper.getSupportDirectory().appendingPathComponent("config.json")
		pluginManager.startWatchingConfig(at: configURL)
        SystemSleepPreventer.shared.start()
    }

    @objc private func tunnelConfigDidChange(_ notification: Notification) {
        if let config = notification.userInfo?[TunnelManager.configurationUserInfoKey] as? TunnelConfiguration {
            tunnelManager.reconfigure(config)
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        SystemSleepPreventer.shared.stop()
        tunnelManager.stop()
    }
    
    private func setStateForUITesting() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }
}
