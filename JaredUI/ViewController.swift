//
//  ViewController.swift
//  JaredUI
//

import Cocoa
import Contacts

class ViewController: NSViewController, DiskAccessDelegate {

    // MARK: - IBOutlets (storyboard compatibility / Touch Bar)
    @IBOutlet weak var JaredStatusLabel: NSTextField!
    @IBOutlet weak var EnableDisableUiButton: NSButton!
    @IBOutlet weak var EnableDisableButton: NSButtonCell!
    @IBOutlet weak var EnableDisableRestApiUiButton: NSButton!
    @IBOutlet weak var RestApiStatusLabel: NSTextField!
    @IBOutlet weak var RestApiStatusImage: NSImageView!
    @IBOutlet weak var statusImage: NSImageView!
    @IBOutlet weak var contactsStatusImage: NSImageView!
    @IBOutlet weak var contactsLabel: NSTextField!
    @IBOutlet weak var contactsButton: NSButton!
    @IBOutlet weak var sendStatusImage: NSImageView!
    @IBOutlet weak var sendStatusLabel: NSTextField!
    @IBOutlet weak var sendStatusButton: NSButton!

    // MARK: - Modern programmatic UI
    private var headerView: NSVisualEffectView!
    private var appIconView: NSImageView!
    private var appTitleLabel: NSTextField!
    private var appSubtitleLabel: NSTextField!
    private var mainToggleButton: NSButton!
    private var jaredRow: StatusRowView!
    private var diskRow: StatusRowView!
    private var apiRow: StatusRowView!
    private var contactsRow: StatusRowView!
    private var sendRow: StatusRowView!

    private var defaults: UserDefaults = .standard
    private let observeKeys = [
        JaredConstants.jaredIsDisabled,
        JaredConstants.restApiIsDisabled,
        JaredConstants.contactsAccess,
        JaredConstants.sendMessageAccess,
        JaredConstants.fullDiskAccess
    ]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = PermissionsHelper.canSendMessages()
        buildUI()
        observeKeys.forEach { defaults.addObserver(self, forKeyPath: $0, options: .new, context: nil) }
        updateTouchBarButton()
    }

    deinit {
        observeKeys.forEach { defaults.removeObserver(self, forKeyPath: $0) }
        if #available(OSX 10.12.2, *) {
            view.window?.unbind(NSBindingName(rawValue: #keyPath(touchBar)))
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if #available(OSX 10.12.2, *) {
            view.window?.unbind(NSBindingName(rawValue: #keyPath(touchBar)))
            view.window?.bind(NSBindingName(rawValue: #keyPath(touchBar)), to: self, withKeyPath: #keyPath(touchBar), options: nil)
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        view.wantsLayer = true

        buildHeader()
        buildScrollContent()
    }

    private func buildHeader() {
        headerView = NSVisualEffectView()
        headerView.material = .sidebar
        headerView.blendingMode = .behindWindow
        headerView.state = .active
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        appIconView = NSImageView()
        appIconView.image = NSApp.applicationIconImage
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.wantsLayer = true
        appIconView.layer?.cornerRadius = 14
        appIconView.layer?.masksToBounds = true
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(appIconView)

        appTitleLabel = label("Jared", size: 18, weight: .semibold)
        headerView.addSubview(appTitleLabel)

        appSubtitleLabel = label("", size: 12, weight: .regular, color: .secondaryLabelColor)
        headerView.addSubview(appSubtitleLabel)

        mainToggleButton = NSButton(title: "", target: self, action: #selector(EnableDisableAction(_:)))
        mainToggleButton.bezelStyle = .rounded
        mainToggleButton.font = .systemFont(ofSize: 12, weight: .medium)
        mainToggleButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(mainToggleButton)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 88),

            appIconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            appIconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            appIconView.widthAnchor.constraint(equalToConstant: 52),
            appIconView.heightAnchor.constraint(equalToConstant: 52),

            appTitleLabel.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 12),
            appTitleLabel.topAnchor.constraint(equalTo: appIconView.topAnchor, constant: 6),

            appSubtitleLabel.leadingAnchor.constraint(equalTo: appTitleLabel.leadingAnchor),
            appSubtitleLabel.topAnchor.constraint(equalTo: appTitleLabel.bottomAnchor, constant: 3),

            mainToggleButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            mainToggleButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            mainToggleButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
        ])
    }

    private func buildScrollContent() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        jaredRow    = StatusRowView(icon: "bubble.left.fill",   iconColor: .systemGreen,  title: "Jared")
        diskRow     = StatusRowView(icon: "internaldrive.fill",  iconColor: .systemBlue,   title: "Full disk access")
        apiRow      = StatusRowView(icon: "network",             iconColor: .systemIndigo,  title: "REST API")
        contactsRow = StatusRowView(icon: "person.fill",         iconColor: .systemOrange, title: "Contacts")
        sendRow     = StatusRowView(icon: "envelope.fill",       iconColor: .systemPurple, title: "Messages automation")

        apiRow.actionButton.target      = self
        apiRow.actionButton.action      = #selector(EnableDisableRestApiAction(_:))
        contactsRow.actionButton.target = self
        contactsRow.actionButton.action = #selector(contactsButtonAction(_:))
        sendRow.actionButton.target     = self
        sendRow.actionButton.action     = #selector(sendStatusButtonAction(_:))
        diskRow.actionButton.target     = self
        diskRow.actionButton.action     = #selector(openDiskPrefs)

        let rows: [NSView] = [
            sectionHeader("Status"),   jaredRow, diskRow,
            separator(),
            sectionHeader("Services"), apiRow,
            separator(),
            sectionHeader("Permissions"), contactsRow, sendRow,
            separator(),
            sectionHeader("Tools"),    actionsRow(),
        ]

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        scroll.documentView = content

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        for row in [jaredRow, diskRow, apiRow, contactsRow, sendRow] as [NSView] {
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
    }

    private func actionsRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let reloadBtn  = toolButton("Reload plugins",      icon: "arrow.clockwise", action: #selector(ReloadButtonPressed(_:)))
        let pluginsBtn = toolButton("Open plugins folder", icon: "folder",          action: #selector(OpenPluginsButtonAction(_:)))

        container.addSubview(reloadBtn)
        container.addSubview(pluginsBtn)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 56),
            reloadBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            reloadBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            pluginsBtn.leadingAnchor.constraint(equalTo: reloadBtn.trailingAnchor, constant: 8),
            pluginsBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    // MARK: - Helpers

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }

    private func sectionHeader(_ title: String) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        let l = NSTextField(labelWithString: title.uppercased())
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: 30),
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    private func separator() -> NSView {
        let b = NSBox(); b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return b
    }

    private func toolButton(_ title: String, icon: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 12)
        b.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        b.imagePosition = .imageLeading
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    // MARK: - Update

    func updateTouchBarButton() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let disabled = self.defaults.bool(forKey: JaredConstants.jaredIsDisabled)
            let noDisk   = !self.defaults.bool(forKey: JaredConstants.fullDiskAccess)
            let apiOff   = self.defaults.bool(forKey: JaredConstants.restApiIsDisabled)

            // Header
            if noDisk {
                self.appSubtitleLabel?.stringValue = "Disk access required"
                self.appSubtitleLabel?.textColor = .systemOrange
                self.mainToggleButton?.title = "Grant access"
                self.mainToggleButton?.contentTintColor = .systemOrange
            } else if disabled {
                self.appSubtitleLabel?.stringValue = "Disabled"
                self.appSubtitleLabel?.textColor = .systemRed
                self.mainToggleButton?.title = "Enable"
                self.mainToggleButton?.contentTintColor = .controlAccentColor
            } else {
                self.appSubtitleLabel?.stringValue = "Running"
                self.appSubtitleLabel?.textColor = .systemGreen
                self.mainToggleButton?.title = "Disable"
                self.mainToggleButton?.contentTintColor = .secondaryLabelColor
            }

            // Legacy Touch Bar outlets
            self.EnableDisableButton?.title  = noDisk ? "Enable Disk Access" : (disabled ? "Enable" : "Disable")
            self.EnableDisableUiButton?.title = self.EnableDisableButton?.title ?? ""
            self.JaredStatusLabel?.stringValue = disabled ? "Jared is currently disabled" : "Jared is currently enabled"
            self.statusImage?.image = NSImage(named: disabled ? NSImage.statusUnavailableName : NSImage.statusAvailableName)

            // Jared row
            self.jaredRow?.update(
                statusText: noDisk ? "Disk access required" : (disabled ? "Disabled" : "Running"),
                state: noDisk ? .warning : (disabled ? .off : .on),
                buttonTitle: nil
            )

            // Disk row
            if noDisk {
                self.diskRow?.update(statusText: "Access denied", state: .error, buttonTitle: "Grant access")
            } else {
                self.diskRow?.update(statusText: "Granted", state: .on, buttonTitle: nil)
            }

            // API row
            if apiOff {
                self.apiRow?.update(statusText: "Disabled", state: .off, buttonTitle: "Enable")
                self.RestApiStatusLabel?.stringValue  = "REST API is currently disabled"
                self.RestApiStatusImage?.image        = NSImage(named: NSImage.statusUnavailableName)
                self.EnableDisableRestApiUiButton?.title = "Enable API"
            } else {
                self.apiRow?.update(statusText: "Running", state: .on, buttonTitle: "Disable")
                self.RestApiStatusLabel?.stringValue  = "REST API is currently enabled"
                self.RestApiStatusImage?.image        = NSImage(named: NSImage.statusAvailableName)
                self.EnableDisableRestApiUiButton?.title = "Disable API"
            }

            // Contacts row
            switch CNAuthorizationStatus(rawValue: self.defaults.integer(forKey: JaredConstants.contactsAccess)) {
            case .authorized:
                self.contactsRow?.update(statusText: "Authorized", state: .on, buttonTitle: "Manage")
                self.contactsLabel?.stringValue    = "Contacts access authorized"
                self.contactsStatusImage?.image    = NSImage(named: NSImage.statusAvailableName)
                self.contactsButton?.title         = "Manage Contacts"
            case .denied:
                self.contactsRow?.update(statusText: "Denied", state: .error, buttonTitle: "Open settings")
                self.contactsLabel?.stringValue    = "Contacts access denied"
                self.contactsStatusImage?.image    = NSImage(named: NSImage.statusUnavailableName)
            case .restricted:
                self.contactsRow?.update(statusText: "Restricted", state: .error, buttonTitle: nil)
                self.contactsLabel?.stringValue    = "Contacts access restricted"
                self.contactsStatusImage?.image    = NSImage(named: NSImage.statusUnavailableName)
            default:
                self.contactsRow?.update(statusText: "Not set", state: .warning, buttonTitle: "Enable")
                self.contactsLabel?.stringValue    = "Contacts access not set"
                self.contactsStatusImage?.image    = NSImage(named: NSImage.statusPartiallyAvailableName)
                self.contactsButton?.title         = "Enable Contacts"
            }

            // Send automation row
            switch AutomationPermissionState(rawValue: self.defaults.integer(forKey: JaredConstants.sendMessageAccess)) {
            case .authorized:
                self.sendRow?.update(statusText: "Authorized", state: .on, buttonTitle: "Manage")
                self.sendStatusLabel?.stringValue  = "Jared can send messages"
                self.sendStatusImage?.image        = NSImage(named: NSImage.statusAvailableName)
                self.sendStatusButton?.title       = "Manage automation"
            case .declined:
                self.sendRow?.update(statusText: "Denied", state: .error, buttonTitle: "Manage")
                self.sendStatusLabel?.stringValue  = "Not permitted to send messages"
                self.sendStatusImage?.image        = NSImage(named: NSImage.statusUnavailableName)
            case .notDetermined:
                self.sendRow?.update(statusText: "Not set", state: .warning, buttonTitle: "Enable")
                self.sendStatusLabel?.stringValue  = "Automation permissions not set"
                self.sendStatusImage?.image        = NSImage(named: NSImage.statusPartiallyAvailableName)
                self.sendStatusButton?.title       = "Enable automation"
            case .notRunning:
                self.sendRow?.update(statusText: "Messages not open", state: .warning, buttonTitle: "Open Messages")
                self.sendStatusLabel?.stringValue  = "Messages is not open"
                self.sendStatusImage?.image        = NSImage(named: NSImage.statusPartiallyAvailableName)
            default:
                self.sendRow?.update(statusText: "Unknown", state: .warning, buttonTitle: "Manage")
                self.sendStatusLabel?.stringValue  = "Messages automation status unknown"
                self.sendStatusImage?.image        = NSImage(named: NSImage.statusPartiallyAvailableName)
            }
        }
    }

    // MARK: - Actions

    @objc private func openDiskPrefs() {
        NSWorkspace.shared.open(URL(string: JaredConstants.fullDiskAcccessUrl)!)
    }

    @IBAction func EnableDisableAction(_ sender: Any) {
        if defaults.bool(forKey: JaredConstants.fullDiskAccess) {
            defaults.set(!defaults.bool(forKey: JaredConstants.jaredIsDisabled), forKey: JaredConstants.jaredIsDisabled)
        } else {
            NSWorkspace.shared.open(URL(string: JaredConstants.fullDiskAcccessUrl)!)
        }
    }

    @IBAction func EnableDisableRestApiAction(_ sender: Any) {
        defaults.set(!defaults.bool(forKey: JaredConstants.restApiIsDisabled), forKey: JaredConstants.restApiIsDisabled)
    }

    @IBAction func contactsButtonAction(_ sender: Any) {
        DispatchQueue.global(qos: .background).async {
            switch CNAuthorizationStatus(rawValue: self.defaults.integer(forKey: JaredConstants.contactsAccess)) {
            case .notDetermined: PermissionsHelper.requestContactsAccess()
            default: NSWorkspace.shared.open(URL(string: JaredConstants.contactsAccessUrl)!)
            }
        }
    }

    @IBAction func sendStatusButtonAction(_ sender: Any) {
        if #available(OSX 10.14, *) {
            switch PermissionsHelper.canSendMessages() {
            case .notRunning:
                NSWorkspace.shared.open(URL(string: JaredConstants.messagesUrl)!)
                sendStatusButtonAction(sender)
            case .authorized, .declined, .unknown:
                NSWorkspace.shared.open(URL(string: JaredConstants.automationAccessUrl)!)
            case .notDetermined:
                PermissionsHelper.requestMessageAutomation()
            }
        }
    }

    @IBAction func OpenPluginsButtonAction(_ sender: Any) {
        let appsupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let pluginDir = appsupport.appendingPathComponent("Jared").appendingPathComponent("Plugins")
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pluginDir.path)
    }

    @IBAction func ReloadButtonPressed(_ sender: Any) {
        (NSApplication.shared.delegate as? AppDelegate)?.pluginManager.reload()
    }

    func displayAccessError() {
        let alert = NSAlert()
        alert.messageText = "Full disk access required"
        alert.informativeText = "Jared needs full disk access to read the Messages database. Enable it in System Settings › Privacy & Security."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: JaredConstants.fullDiskAcccessUrl)!)
        }
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath, observeKeys.contains(keyPath) else { return }
        updateTouchBarButton()
    }

    override var representedObject: Any? { didSet {} }
}

// MARK: - StatusRowView

enum RowState { case on, off, warning, error }

final class StatusRowView: NSView {
    let actionButton = NSButton()
    private let iconContainer = NSView()
    private let iconView      = NSImageView()
    private let titleLabel    = NSTextField(labelWithString: "")
    private let statusLabel   = NSTextField(labelWithString: "")

    init(icon: String, iconColor: NSColor, title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(icon: icon, iconColor: iconColor, title: title)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(icon: String, iconColor: NSColor, title: String) {
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 8
        iconContainer.layer?.backgroundColor = iconColor.withAlphaComponent(0.12).cgColor
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            iconView.image = img
        }
        iconView.contentTintColor = iconColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        titleLabel.font      = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.stringValue = title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font      = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        actionButton.bezelStyle = .rounded
        actionButton.font       = .systemFont(ofSize: 11)
        actionButton.isHidden   = true
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconContainer)
        addSubview(titleLabel)
        addSubview(statusLabel)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),

            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 32),
            iconContainer.heightAnchor.constraint(equalToConstant: 32),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 3),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func update(statusText: String, state: RowState, buttonTitle: String?) {
        statusLabel.stringValue = statusText
        switch state {
        case .on:      statusLabel.textColor = .systemGreen
        case .off:     statusLabel.textColor = .tertiaryLabelColor
        case .warning: statusLabel.textColor = .systemOrange
        case .error:   statusLabel.textColor = .systemRed
        }
        if let title = buttonTitle {
            actionButton.title  = title
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
    }
}
