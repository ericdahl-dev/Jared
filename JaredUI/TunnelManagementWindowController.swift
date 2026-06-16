//
//  TunnelManagementWindowController.swift
//  JaredUI
//

import Cocoa

class TunnelManagementWindowController: NSWindowController {

    // MARK: - UI
    private var providerPopup:   NSPopUpButton!
    private var enabledCheck:    NSButton!
    private var statusLabel:     NSTextField!
    private var copyURLBtn:      NSButton!
    private var tokenSection:    NSView!
    private var tokenField:      NSSecureTextField!
    private var saveTokenBtn:    NSButton!
    private var clearTokenBtn:   NSButton!

    // MARK: - State
    private let configURL = ConfigurationHelper.getSupportDirectory()
        .appendingPathComponent("config.json")
    private let keychain  = KeychainStore()

    private var currentPublicURL: URL?

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tunnel Management"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
        loadConfig()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tunnelStateDidChange(_:)),
            name: TunnelManager.publicURLDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI setup

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        // ── Provider section ──────────────────────────────────────────
        let providerTitle = sectionLabel("Provider")
        let providerSub   = bodyLabel("Choose which tool creates the public tunnel URL.")
        providerSub.textColor = .secondaryLabelColor
        providerSub.lineBreakMode = .byWordWrapping
        providerSub.maximumNumberOfLines = 2

        providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        providerPopup.addItem(withTitle: "Cloudflare (cloudflared)")
        providerPopup.addItem(withTitle: "ngrok")
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged(_:))
        providerPopup.translatesAutoresizingMaskIntoConstraints = false

        enabledCheck = NSButton(checkboxWithTitle: "Enable tunnel", target: nil, action: nil)
        enabledCheck.translatesAutoresizingMaskIntoConstraints = false

        let sep1 = separator()

        // ── Status section ────────────────────────────────────────────
        let statusTitle = sectionLabel("Status")

        statusLabel = bodyLabel("—")
        statusLabel.isSelectable = true
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        copyURLBtn = NSButton(title: "Copy URL", target: self, action: #selector(copyURL))
        copyURLBtn.bezelStyle = .rounded
        copyURLBtn.font = .systemFont(ofSize: 11)
        copyURLBtn.isHidden = true
        copyURLBtn.translatesAutoresizingMaskIntoConstraints = false

        let sep2 = separator()

        // ── ngrok token section ───────────────────────────────────────
        tokenSection = NSView()
        tokenSection.translatesAutoresizingMaskIntoConstraints = false

        let tokenTitle = sectionLabel("ngrok Auth Token")
        tokenTitle.translatesAutoresizingMaskIntoConstraints = false

        let tokenSub = bodyLabel("Required for ngrok. Stored in Keychain.")
        tokenSub.textColor = .secondaryLabelColor
        tokenSub.translatesAutoresizingMaskIntoConstraints = false

        tokenField = NSSecureTextField()
        tokenField.placeholderString = "Paste auth token here"
        tokenField.bezelStyle = .roundedBezel
        tokenField.translatesAutoresizingMaskIntoConstraints = false

        saveTokenBtn = NSButton(title: "Save Token", target: self, action: #selector(saveToken))
        saveTokenBtn.bezelStyle = .rounded
        saveTokenBtn.font = .systemFont(ofSize: 11)
        saveTokenBtn.translatesAutoresizingMaskIntoConstraints = false

        clearTokenBtn = NSButton(title: "Clear Token", target: self, action: #selector(clearToken))
        clearTokenBtn.bezelStyle = .rounded
        clearTokenBtn.font = .systemFont(ofSize: 11)
        clearTokenBtn.translatesAutoresizingMaskIntoConstraints = false

        let tokenBtnRow = NSStackView(views: [saveTokenBtn, clearTokenBtn])
        tokenBtnRow.orientation = .horizontal
        tokenBtnRow.spacing = 8
        tokenBtnRow.translatesAutoresizingMaskIntoConstraints = false

        for v in [tokenTitle, tokenSub, tokenField, tokenBtnRow] as [NSView] {
            tokenSection.addSubview(v)
        }

        NSLayoutConstraint.activate([
            tokenSection.heightAnchor.constraint(equalToConstant: 110),

            tokenTitle.topAnchor.constraint(equalTo: tokenSection.topAnchor),
            tokenTitle.leadingAnchor.constraint(equalTo: tokenSection.leadingAnchor),

            tokenSub.topAnchor.constraint(equalTo: tokenTitle.bottomAnchor, constant: 2),
            tokenSub.leadingAnchor.constraint(equalTo: tokenSection.leadingAnchor),
            tokenSub.trailingAnchor.constraint(equalTo: tokenSection.trailingAnchor),

            tokenField.topAnchor.constraint(equalTo: tokenSub.bottomAnchor, constant: 8),
            tokenField.leadingAnchor.constraint(equalTo: tokenSection.leadingAnchor),
            tokenField.trailingAnchor.constraint(equalTo: tokenSection.trailingAnchor),

            tokenBtnRow.topAnchor.constraint(equalTo: tokenField.bottomAnchor, constant: 8),
            tokenBtnRow.leadingAnchor.constraint(equalTo: tokenSection.leadingAnchor),
        ])

        // ── Bottom bar ────────────────────────────────────────────────
        let sep3 = separator()

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false

        // ── Layout ────────────────────────────────────────────────────
        for v in [providerTitle, providerSub, providerPopup!, enabledCheck!, sep1,
                  statusTitle, statusLabel!, copyURLBtn!, sep2, tokenSection!,
                  sep3, cancelBtn, saveBtn] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cv.addSubview(v)
        }

        let margin: CGFloat = 20

        NSLayoutConstraint.activate([
            // Provider
            providerTitle.topAnchor.constraint(equalTo: cv.topAnchor, constant: margin),
            providerTitle.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: margin),
            providerTitle.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -margin),

            providerSub.topAnchor.constraint(equalTo: providerTitle.bottomAnchor, constant: 4),
            providerSub.leadingAnchor.constraint(equalTo: providerTitle.leadingAnchor),
            providerSub.trailingAnchor.constraint(equalTo: providerTitle.trailingAnchor),

            providerPopup.topAnchor.constraint(equalTo: providerSub.bottomAnchor, constant: 8),
            providerPopup.leadingAnchor.constraint(equalTo: providerTitle.leadingAnchor),
            providerPopup.widthAnchor.constraint(equalToConstant: 220),

            enabledCheck.topAnchor.constraint(equalTo: providerPopup.bottomAnchor, constant: 10),
            enabledCheck.leadingAnchor.constraint(equalTo: providerTitle.leadingAnchor),

            sep1.topAnchor.constraint(equalTo: enabledCheck.bottomAnchor, constant: 16),
            sep1.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep1.trailingAnchor.constraint(equalTo: cv.trailingAnchor),

            // Status
            statusTitle.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: 14),
            statusTitle.leadingAnchor.constraint(equalTo: providerTitle.leadingAnchor),

            statusLabel.topAnchor.constraint(equalTo: statusTitle.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: providerTitle.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -margin),

            copyURLBtn.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            copyURLBtn.leadingAnchor.constraint(equalTo: providerTitle.leadingAnchor),

            sep2.topAnchor.constraint(equalTo: copyURLBtn.bottomAnchor, constant: 14),
            sep2.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep2.trailingAnchor.constraint(equalTo: cv.trailingAnchor),

            // ngrok token
            tokenSection.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: 14),
            tokenSection.leadingAnchor.constraint(equalTo: providerTitle.leadingAnchor),
            tokenSection.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -margin),

            // Bottom bar
            sep3.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep3.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            sep3.bottomAnchor.constraint(equalTo: saveBtn.topAnchor, constant: -12),

            saveBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -margin),
            saveBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -margin),

            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            cancelBtn.centerYAnchor.constraint(equalTo: saveBtn.centerYAnchor),
        ])
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13, weight: .semibold)
        return f
    }

    private func bodyLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 12)
        return f
    }

    private func separator() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    // MARK: - Data

    private func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let webServer = json["webServer"] as? [String: Any] else {
            updateProviderVisibility()
            return
        }

        let tunnel = webServer["tunnel"] as? [String: Any]
        let isEnabled  = tunnel?["enabled"] as? Bool ?? false
        let providerStr = tunnel?["provider"] as? String ?? "cloudflared"

        enabledCheck.state = isEnabled ? .on : .off
        providerPopup.selectItem(at: providerStr == "ngrok" ? 1 : 0)

        // Show placeholder if token exists in keychain
        if keychain.secret(for: TunnelManager.ngrokKeychainAccount) != nil {
            tokenField.placeholderString = "Token saved — paste new value to replace"
        }

        updateProviderVisibility()
        updateStatusLabel()
    }

    private func updateProviderVisibility() {
        let isNgrok = providerPopup.indexOfSelectedItem == 1
        tokenSection.isHidden = !isNgrok
    }

    private func updateStatusLabel() {
        if let url = currentPublicURL {
            statusLabel.stringValue = url.absoluteString
            statusLabel.textColor   = .systemGreen
            copyURLBtn.isHidden = false
        } else {
            statusLabel.stringValue = "No active tunnel"
            statusLabel.textColor   = .secondaryLabelColor
            copyURLBtn.isHidden = true
        }
    }

    // MARK: - Notifications

    @objc private func tunnelStateDidChange(_ notification: Notification) {
        currentPublicURL = notification.userInfo?[TunnelManager.publicURLUserInfoKey] as? URL
        DispatchQueue.main.async { self.updateStatusLabel() }
    }

    // MARK: - Actions

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        updateProviderVisibility()
    }

    @objc private func copyURL() {
        guard let url = currentPublicURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    @objc private func saveToken() {
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        keychain.save(secret: token, for: TunnelManager.ngrokKeychainAccount)
        tokenField.stringValue = ""
        tokenField.placeholderString = "Token saved — paste new value to replace"
    }

    @objc private func clearToken() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Remove ngrok auth token?"
        alert.informativeText = "The token will be deleted from Keychain."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.keychain.delete(for: TunnelManager.ngrokKeychainAccount)
            self.tokenField.stringValue = ""
            self.tokenField.placeholderString = "Paste auth token here"
        }
    }

    @objc private func saveAction() {
        let isEnabled   = enabledCheck.state == .on
        let providerStr = providerPopup.indexOfSelectedItem == 1 ? "ngrok" : "cloudflared"

        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var webServer = json["webServer"] as? [String: Any] ?? [:]
        webServer["tunnel"] = ["enabled": isEnabled, "provider": providerStr]
        json["webServer"] = webServer

        guard let out    = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: out, encoding: .utf8) else { return }
        try? pretty.write(to: configURL, atomically: true, encoding: .utf8)

        let provider: TunnelProvider = providerStr == "ngrok" ? .ngrok : .cloudflared
        let newConfig = TunnelConfiguration(enabled: isEnabled, provider: provider)
        NotificationCenter.default.post(
            name: TunnelManager.configurationDidChangeNotification,
            object: self,
            userInfo: [TunnelManager.configurationUserInfoKey: newConfig]
        )

        window?.close()
    }

    @objc private func cancelAction() {
        window?.close()
    }
}
