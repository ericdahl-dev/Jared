//
//  WebhookManagementWindowController.swift
//  JaredUI
//

import Cocoa

class WebhookManagementWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {

    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var webhooks: [[String: Any]] = []

    private let configURL = ConfigurationHelper.getSupportDirectory()
        .appendingPathComponent("config.json")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Webhooks"
        window.isMovableByWindowBackground = true
        self.init(window: window)
        setupUI()
        loadWebhooks()
    }

    // MARK: - UI

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true
        cv.addSubview(scrollView)

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 40
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let enabledCol = NSTableColumn(identifier: .init("enabled"))
        enabledCol.title = "On"
        enabledCol.width = 36
        enabledCol.resizingMask = []
        tableView.addTableColumn(enabledCol)

        let urlCol = NSTableColumn(identifier: .init("url"))
        urlCol.title = "URL"
        urlCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(urlCol)

        let modeCol = NSTableColumn(identifier: .init("mode"))
        modeCol.title = "Mode"
        modeCol.width = 76
        modeCol.resizingMask = []
        tableView.addTableColumn(modeCol)

        let testCol = NSTableColumn(identifier: .init("test"))
        testCol.title = ""
        testCol.width = 52
        testCol.resizingMask = []
        tableView.addTableColumn(testCol)

        let deleteCol = NSTableColumn(identifier: .init("delete"))
        deleteCol.title = ""
        deleteCol.width = 36
        deleteCol.resizingMask = []
        tableView.addTableColumn(deleteCol)
        tableView.doubleAction = #selector(editSelectedRow)
        tableView.target = self

        scrollView.documentView = tableView

        emptyLabel = NSTextField(labelWithString: "No webhooks configured.\nClick \"+ Add\" to get started.")
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        cv.addSubview(emptyLabel)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(statusLabel)

        let addButton = NSButton(title: "+ Add", target: self, action: #selector(addWebhook))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(addButton)
        cv.addSubview(doneButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            addButton.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            addButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),

            statusLabel.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -12),

            doneButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            doneButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Data

    private func loadWebhooks() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            webhooks = []
            refresh()
            return
        }
        webhooks = json["webhooks"] as? [[String: Any]] ?? []
        refresh()
    }

    private func save() {
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        json["webhooks"] = webhooks
        guard let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: out, encoding: .utf8) else { return }
        try? pretty.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func refresh() {
        tableView.reloadData()
        emptyLabel.isHidden = !webhooks.isEmpty
    }

    private func setStatus(_ text: String, color: NSColor = .secondaryLabelColor) {
        DispatchQueue.main.async {
            self.statusLabel.stringValue = text
            self.statusLabel.textColor = color
        }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { webhooks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hook = webhooks[row]
        switch tableColumn?.identifier.rawValue {

        case "enabled":
            let cb = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            cb.tag = row
            cb.state = (hook["enabled"] as? Bool ?? true) ? .on : .off
            return cb

        case "url":
            let field = NSTextField(labelWithString: hook["url"] as? String ?? "")
            field.lineBreakMode = .byTruncatingMiddle
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.textColor = (hook["enabled"] as? Bool ?? true) ? .labelColor : .tertiaryLabelColor
            return field

        case "mode":
            let mode = hook["mode"] as? String ?? "notify"
            let field = NSTextField(labelWithString: mode)
            field.textColor = mode == "command" ? .systemOrange : .systemBlue
            field.font = .systemFont(ofSize: 11, weight: .semibold)
            return field

        case "test":
            let btn = NSButton(title: "Test", target: self, action: #selector(sendTest(_:)))
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 11)
            btn.tag = row
            return btn

        case "delete":
            let btn = NSButton(title: "×", target: self, action: #selector(deleteRow(_:)))
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 14)
            btn.contentTintColor = .systemRed
            btn.tag = row
            return btn

        default:
            return nil
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard row < webhooks.count else { return }
        webhooks[row]["enabled"] = sender.state == .on
        tableView.reloadData()
        save()
    }

    @objc private func deleteRow(_ sender: NSButton) {
        let row = sender.tag
        guard row < webhooks.count else { return }
        webhooks.remove(at: row)
        refresh()
        save()
    }

    @objc private func sendTest(_ sender: NSButton) {
        let row = sender.tag
        guard row < webhooks.count,
              let urlString = webhooks[row]["url"] as? String,
              let url = URL(string: urlString) else {
            setStatus("Invalid URL", color: .systemRed)
            return
        }

        setStatus("Sending…", color: .secondaryLabelColor)

        let payload: [String: Any] = [
            "text": "/test",
            "sender": ["handle": "test@example.com", "name": "Test"],
            "chat": ["chatIdentifier": "test@example.com", "name": "Test Chat"],
            "isFromMe": false,
            "date": ISO8601DateFormatter().string(from: Date()),
            "_jared_test": true,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Jared/test", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                self?.setStatus("Error: \(error.localizedDescription)", color: .systemRed)
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) {
                self?.setStatus("✓ \(code) — test delivered", color: .systemGreen)
            } else {
                self?.setStatus("✗ HTTP \(code)", color: .systemOrange)
            }
        }.resume()
    }

    // MARK: - Edit / Add sheets

    @objc private func editSelectedRow() {
        let row = tableView.clickedRow
        guard row >= 0, row < webhooks.count else { return }
        editWebhook(at: row)
    }

    private func editWebhook(at row: Int) {
        let hook = webhooks[row]

        let alert = NSAlert()
        alert.messageText = "Edit Webhook"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let urlField = NSTextField(frame: NSRect(x: 0, y: 34, width: 380, height: 22))
        urlField.stringValue = hook["url"] as? String ?? ""
        urlField.placeholderString = "https://example.com/webhook"

        let modeLabel = NSTextField(labelWithString: "Mode:")
        modeLabel.frame = NSRect(x: 0, y: 4, width: 40, height: 22)

        let modeButton = NSPopUpButton(frame: NSRect(x: 46, y: 2, width: 120, height: 26))
        modeButton.addItem(withTitle: "notify")
        modeButton.addItem(withTitle: "command")
        let currentMode = hook["mode"] as? String ?? "notify"
        modeButton.selectItem(withTitle: currentMode)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 60))
        container.addSubview(urlField)
        container.addSubview(modeLabel)
        container.addSubview(modeButton)
        alert.accessoryView = container

        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return }
            let mode = modeButton.selectedItem?.title ?? "notify"
            self?.webhooks[row]["url"] = url
            self?.webhooks[row]["mode"] = mode
            self?.refresh()
            self?.save()
        }
    }

    @objc private func addWebhook() {
        let alert = NSAlert()
        alert.messageText = "Add Webhook"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let urlField = NSTextField(frame: NSRect(x: 0, y: 34, width: 380, height: 22))
        urlField.placeholderString = "https://example.com/webhook"

        let modeLabel = NSTextField(labelWithString: "Mode:")
        modeLabel.frame = NSRect(x: 0, y: 4, width: 40, height: 22)

        let modeButton = NSPopUpButton(frame: NSRect(x: 46, y: 2, width: 120, height: 26))
        modeButton.addItem(withTitle: "notify")
        modeButton.addItem(withTitle: "command")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 60))
        container.addSubview(urlField)
        container.addSubview(modeLabel)
        container.addSubview(modeButton)
        alert.accessoryView = container

        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return }
            let mode = modeButton.selectedItem?.title ?? "notify"
            self?.webhooks.append(["url": url, "mode": mode, "enabled": true])
            self?.refresh()
            self?.save()
        }
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
