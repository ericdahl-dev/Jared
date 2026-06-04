//
//  MenuBarManager.swift
//  JaredUI
//

import Cocoa

class MenuBarManager {
    private var statusItem: NSStatusItem
    private var pluginManager: PluginManager

    init(pluginManager: PluginManager) {
        self.pluginManager = pluginManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        buildMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func updateIcon() {
        let isDisabled = UserDefaults.standard.bool(forKey: JaredConstants.jaredIsDisabled)
        statusItem.button?.title = isDisabled ? "💤" : "💬"
        statusItem.button?.toolTip = isDisabled ? "Jared — disabled" : "Jared — active"
    }

    private func buildMenu() {
        let menu = NSMenu()

        let statusTitle = UserDefaults.standard.bool(forKey: JaredConstants.jaredIsDisabled)
            ? "Status: Disabled"
            : "Status: Enabled"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(
            title: UserDefaults.standard.bool(forKey: JaredConstants.jaredIsDisabled) ? "Enable Jared" : "Disable Jared",
            action: #selector(toggleEnabled),
            keyEquivalent: "t"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let reloadItem = NSMenuItem(title: "Reload Plugins", action: #selector(reloadPlugins), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(NSMenuItem.separator())

        let showItem = NSMenuItem(title: "Show Status Window", action: #selector(showWindow), keyEquivalent: "s")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Jared", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        let current = UserDefaults.standard.bool(forKey: JaredConstants.jaredIsDisabled)
        UserDefaults.standard.set(!current, forKey: JaredConstants.jaredIsDisabled)
    }

    @objc private func reloadPlugins() {
        pluginManager.reload()
    }

    @objc private func showWindow() {
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func defaultsChanged() {
        updateIcon()
        buildMenu()
    }
}
