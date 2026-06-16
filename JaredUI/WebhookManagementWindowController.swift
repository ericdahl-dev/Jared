//
//  WebhookManagementWindowController.swift
//  JaredUI
//

import Cocoa

// MARK: - Endpoint list cell

private class EndpointCellView: NSTableCellView {
    let hostLabel   = NSTextField(labelWithString: "")
    let statusBadge = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        hostLabel.font = .systemFont(ofSize: 13)
        hostLabel.lineBreakMode = .byTruncatingMiddle
        hostLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBadge.font = .systemFont(ofSize: 10, weight: .medium)
        statusBadge.translatesAutoresizingMaskIntoConstraints = false

        addSubview(hostLabel)
        addSubview(statusBadge)

        NSLayoutConstraint.activate([
            hostLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            hostLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hostLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),

            statusBadge.leadingAnchor.constraint(equalTo: hostLabel.leadingAnchor),
            statusBadge.topAnchor.constraint(equalTo: hostLabel.bottomAnchor, constant: 2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with hook: [String: Any]) {
        let url     = hook["url"] as? String ?? ""
        let enabled = hook["enabled"] as? Bool ?? true
        hostLabel.stringValue  = URL(string: url)?.host ?? url
        hostLabel.textColor    = enabled ? .labelColor : .tertiaryLabelColor
        statusBadge.stringValue = enabled ? "Active" : "Disabled"
        statusBadge.textColor   = enabled ? .systemGreen : .secondaryLabelColor
    }
}

// MARK: - Delivery history cell

private class DeliveryCellView: NSTableCellView {
    let statusLabel = NSTextField(labelWithString: "")
    let timeLabel   = NSTextField(labelWithString: "")
    let idLabel     = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        for f in [statusLabel, timeLabel, idLabel] {
            f.translatesAutoresizingMaskIntoConstraints = false
            addSubview(f)
        }
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        timeLabel.font   = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        idLabel.font     = .monospacedSystemFont(ofSize: 10, weight: .regular)
        idLabel.textColor = .tertiaryLabelColor
        idLabel.lineBreakMode = .byTruncatingMiddle

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            timeLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            timeLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            idLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            idLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            idLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    func configure(with record: WebhookDeliveryRecord) {
        if let code = record.statusCode {
            statusLabel.stringValue = (200...299).contains(code) ? "✓ \(code)" : "✗ \(code)"
            statusLabel.textColor   = (200...299).contains(code) ? .systemGreen : .systemOrange
        } else if let err = record.errorDescription {
            statusLabel.stringValue = "Error"
            statusLabel.textColor   = .systemRed
            idLabel.stringValue     = err
        }
        if record.attempt > 1 { statusLabel.stringValue += "  (attempt \(record.attempt))" }
        timeLabel.stringValue = Self.formatter.localizedString(for: record.date, relativeTo: Date())
        if record.errorDescription == nil {
            idLabel.stringValue = record.deliveryId
        }
    }
}

// MARK: - Window controller

class WebhookManagementWindowController: NSWindowController,
                                          NSTableViewDelegate,
                                          NSTableViewDataSource,
                                          NSTextFieldDelegate {

    // Left panel
    private var endpointTable:  NSTableView!

    // Right panel
    private var detailBox:      NSView!
    private var urlField:       NSTextField!
    private var urlValidationLabel: NSTextField!
    private var enabledCheck:   NSButton!
    private var routesLabel:    NSTextField!
    private var deliveryStatus: NSTextField!
    private var saveBtn:           NSButton!
    private var deleteBtn:         NSButton!
    private var openBtn:           NSButton!
    private var testBtn:           NSButton!
    private var rotateSecretBtn:   NSButton!
    private var historyTable:   NSTableView!
    private var historyStatus:  NSTextField!
    private var emptyDetail:    NSTextField!

    private var webhooks: [[String: Any]] = []
    private let deliveryStore = WebHookManager.defaultDeliveryStore()
    private var deliveryLog: [WebhookDeliveryRecord] = []

    private var selectedRow: Int = -1 {
        didSet { updateDetail() }
    }

    private let configURL = ConfigurationHelper.getSupportDirectory()
        .appendingPathComponent("config.json")

    // MARK: Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Webhook Management"
        window.minSize = NSSize(width: 680, height: 400)
        self.init(window: window)
        setupUI()
        loadWebhooks()
        deliveryLog = deliveryStore.load()
        NotificationCenter.default.addObserver(self, selector: #selector(deliveryRecorded(_:)),
                                               name: .webhookDelivered, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI setup

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        // ── Split view ─────────────────────────────────────────────
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        cv.addSubview(split)

        // ── Left panel ─────────────────────────────────────────────
        let leftPanel = NSView()
        split.addArrangedSubview(leftPanel)

        let leftTitle = sectionTitle("Endpoints")
        let leftSub   = bodyLabel("Add, remove, and review configured webhooks.")
        leftSub.lineBreakMode = .byWordWrapping
        leftSub.maximumNumberOfLines = 2

        let newBtn = NSButton(title: "New", target: self, action: #selector(addWebhook))
        newBtn.bezelStyle = .rounded
        let refreshBtn = NSButton(title: "Refresh", target: self, action: #selector(refresh(_:)))
        refreshBtn.bezelStyle = .rounded
        let btnStack = NSStackView(views: [newBtn, refreshBtn])
        btnStack.orientation = .horizontal
        btnStack.spacing = 8

        let leftScrollView = NSScrollView()
        leftScrollView.borderType = .noBorder
        leftScrollView.hasVerticalScroller = true
        leftScrollView.autohidesScrollers = true
        leftScrollView.drawsBackground = false

        endpointTable = NSTableView()
        endpointTable.style = .inset
        endpointTable.headerView = nil
        endpointTable.rowHeight = 46
        endpointTable.backgroundColor = .clear
        endpointTable.selectionHighlightStyle = .regular
        endpointTable.delegate = self
        endpointTable.dataSource = self
        let epCol = NSTableColumn(identifier: .init("endpoint"))
        epCol.resizingMask = .autoresizingMask
        endpointTable.addTableColumn(epCol)
        leftScrollView.documentView = endpointTable

        for v in [leftTitle, leftSub, btnStack, leftScrollView] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            leftPanel.addSubview(v)
        }
        NSLayoutConstraint.activate([
            leftTitle.topAnchor.constraint(equalTo: leftPanel.topAnchor, constant: 16),
            leftTitle.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor, constant: 14),
            leftTitle.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: -8),

            leftSub.topAnchor.constraint(equalTo: leftTitle.bottomAnchor, constant: 2),
            leftSub.leadingAnchor.constraint(equalTo: leftTitle.leadingAnchor),
            leftSub.trailingAnchor.constraint(equalTo: leftTitle.trailingAnchor),

            btnStack.topAnchor.constraint(equalTo: leftSub.bottomAnchor, constant: 10),
            btnStack.leadingAnchor.constraint(equalTo: leftTitle.leadingAnchor),

            leftScrollView.topAnchor.constraint(equalTo: btnStack.bottomAnchor, constant: 8),
            leftScrollView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            leftScrollView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            leftScrollView.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),

            leftPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
        ])
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)

        // ── Right panel ────────────────────────────────────────────
        let rightPanel = NSView()
        split.addArrangedSubview(rightPanel)

        // Empty state shown when nothing selected
        emptyDetail = bodyLabel("Select an endpoint to view details.")
        emptyDetail.textColor = .tertiaryLabelColor
        emptyDetail.alignment = .center
        emptyDetail.translatesAutoresizingMaskIntoConstraints = false
        rightPanel.addSubview(emptyDetail)

        detailBox = NSView()
        detailBox.translatesAutoresizingMaskIntoConstraints = false
        detailBox.isHidden = true
        rightPanel.addSubview(detailBox)

        buildDetailPane(in: detailBox)

        NSLayoutConstraint.activate([
            emptyDetail.centerXAnchor.constraint(equalTo: rightPanel.centerXAnchor),
            emptyDetail.centerYAnchor.constraint(equalTo: rightPanel.centerYAnchor),

            detailBox.topAnchor.constraint(equalTo: rightPanel.topAnchor),
            detailBox.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor),
            detailBox.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            detailBox.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
        ])

        // Initial split position
        DispatchQueue.main.async {
            split.setPosition(220, ofDividerAt: 0)
        }

        // Bottom bar with Done button
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.0).cgColor
        cv.addSubview(bottomBar)

        let sep2 = NSView()
        sep2.translatesAutoresizingMaskIntoConstraints = false
        sep2.wantsLayer = true
        sep2.layer?.backgroundColor = NSColor.separatorColor.cgColor
        cv.addSubview(sep2)

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(doneBtn)

        NSLayoutConstraint.activate([
            sep2.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep2.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            sep2.heightAnchor.constraint(equalToConstant: 1),

            bottomBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 44),
            sep2.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            doneBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            doneBtn.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
        ])

        // Shrink split view to leave room for bottom bar
        split.autoresizingMask = []
        split.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: cv.topAnchor),
            split.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: sep2.topAnchor),
        ])
    }

    private func buildDetailPane(in box: NSView) {
        let selectedTitle  = sectionTitle("Selected Webhook")
        let urlLabel       = bodyLabel("Endpoint URL")
        urlLabel.textColor = .secondaryLabelColor

        urlField = NSTextField()
        urlField.placeholderString = "https://example.com/webhook"
        urlField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.bezelStyle = .roundedBezel
        urlField.usesSingleLineMode = false
        urlField.cell?.wraps = true
        urlField.cell?.isScrollable = false
        urlField.delegate = self

        urlValidationLabel = bodyLabel("")
        urlValidationLabel.font = .systemFont(ofSize: 11)
        urlValidationLabel.textColor = .systemRed
        urlValidationLabel.isHidden = true

        enabledCheck = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)

        routesLabel = bodyLabel("")
        routesLabel.textColor = .secondaryLabelColor
        routesLabel.font = .systemFont(ofSize: 12)

        let enableRow = NSStackView(views: [enabledCheck, routesLabel])
        enableRow.orientation = .horizontal
        enableRow.spacing = 10

        deliveryStatus = bodyLabel("No deliveries recorded yet")
        deliveryStatus.textColor = .secondaryLabelColor
        deliveryStatus.font = .systemFont(ofSize: 12)

        saveBtn          = actionButton("Save Changes",       isPrimary: true)
        deleteBtn        = actionButton("Delete",             isPrimary: false)
        openBtn          = actionButton("Open Endpoint",      isPrimary: false)
        testBtn          = actionButton("Send Test Payload",  isPrimary: false)
        rotateSecretBtn  = actionButton("Rotate HMAC Secret", isPrimary: false)
        saveBtn.action          = #selector(saveChanges)
        deleteBtn.action        = #selector(deleteSelected)
        openBtn.action          = #selector(openEndpoint)
        testBtn.action          = #selector(sendTest)
        rotateSecretBtn.action  = #selector(rotateHMACSecret)
        for b in [saveBtn!, deleteBtn!, openBtn!, testBtn!, rotateSecretBtn!] { b.target = self }

        let topBtnRow    = NSStackView(views: [saveBtn, deleteBtn])
        topBtnRow.orientation = .horizontal
        topBtnRow.spacing = 8
        let midBtnRow    = NSStackView(views: [openBtn, testBtn])
        midBtnRow.orientation = .horizontal
        midBtnRow.spacing = 8
        let botBtnRow    = NSStackView(views: [rotateSecretBtn])
        botBtnRow.orientation = .horizontal
        botBtnRow.spacing = 8
        let buttonRow = NSStackView(views: [topBtnRow, midBtnRow, botBtnRow])
        buttonRow.orientation = .vertical
        buttonRow.alignment = .leading
        buttonRow.spacing = 6

        let sep = NSBox(); sep.boxType = .separator

        let historyTitle = sectionTitle("Delivery History")
        let historySub   = bodyLabel("History reflects the most recent persisted deliveries (newest first).")
        historySub.textColor = .secondaryLabelColor
        historySub.lineBreakMode = .byWordWrapping
        historySub.maximumNumberOfLines = 2

        let histScrollView = NSScrollView()
        histScrollView.borderType = .noBorder
        histScrollView.hasVerticalScroller = true
        histScrollView.autohidesScrollers = true
        histScrollView.drawsBackground = false

        historyTable = NSTableView()
        historyTable.style = .inset
        historyTable.headerView = nil
        historyTable.rowHeight = 40
        historyTable.backgroundColor = .clear
        historyTable.selectionHighlightStyle = .none
        historyTable.delegate = self
        historyTable.dataSource = self
        let hCol = NSTableColumn(identifier: .init("history"))
        hCol.resizingMask = .autoresizingMask
        historyTable.addTableColumn(hCol)
        histScrollView.documentView = historyTable

        historyStatus = bodyLabel("No deliveries recorded yet")
        historyStatus.textColor = .tertiaryLabelColor
        historyStatus.alignment = .center
        historyStatus.font = .systemFont(ofSize: 12)

        for v in [selectedTitle, urlLabel, urlField!, urlValidationLabel!, enableRow, deliveryStatus,
                  buttonRow, sep, historyTitle, historySub,
                  histScrollView, historyStatus] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(v)
        }

        NSLayoutConstraint.activate([
            selectedTitle.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            selectedTitle.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 20),
            selectedTitle.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -20),

            urlLabel.topAnchor.constraint(equalTo: selectedTitle.bottomAnchor, constant: 14),
            urlLabel.leadingAnchor.constraint(equalTo: selectedTitle.leadingAnchor),

            urlField.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 4),
            urlField.leadingAnchor.constraint(equalTo: selectedTitle.leadingAnchor),
            urlField.trailingAnchor.constraint(equalTo: selectedTitle.trailingAnchor),
            urlField.heightAnchor.constraint(greaterThanOrEqualToConstant: 42),

            urlValidationLabel.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 4),
            urlValidationLabel.leadingAnchor.constraint(equalTo: selectedTitle.leadingAnchor),
            urlValidationLabel.trailingAnchor.constraint(equalTo: selectedTitle.trailingAnchor),

            enableRow.topAnchor.constraint(equalTo: urlValidationLabel.bottomAnchor, constant: 6),
            enableRow.leadingAnchor.constraint(equalTo: selectedTitle.leadingAnchor),

            deliveryStatus.topAnchor.constraint(equalTo: enableRow.bottomAnchor, constant: 6),
            deliveryStatus.leadingAnchor.constraint(equalTo: selectedTitle.leadingAnchor),

            buttonRow.topAnchor.constraint(equalTo: deliveryStatus.bottomAnchor, constant: 14),
            buttonRow.leadingAnchor.constraint(equalTo: selectedTitle.leadingAnchor),

            sep.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 16),
            sep.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: box.trailingAnchor),

            historyTitle.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 14),
            historyTitle.leadingAnchor.constraint(equalTo: selectedTitle.leadingAnchor),
            historyTitle.trailingAnchor.constraint(equalTo: selectedTitle.trailingAnchor),

            historySub.topAnchor.constraint(equalTo: historyTitle.bottomAnchor, constant: 2),
            historySub.leadingAnchor.constraint(equalTo: selectedTitle.leadingAnchor),
            historySub.trailingAnchor.constraint(equalTo: selectedTitle.trailingAnchor),

            histScrollView.topAnchor.constraint(equalTo: historySub.bottomAnchor, constant: 8),
            histScrollView.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            histScrollView.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            histScrollView.bottomAnchor.constraint(equalTo: box.bottomAnchor),

            historyStatus.centerXAnchor.constraint(equalTo: histScrollView.centerXAnchor),
            historyStatus.centerYAnchor.constraint(equalTo: histScrollView.centerYAnchor),
        ])
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 15, weight: .semibold)
        return f
    }

    private func bodyLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 12)
        return f
    }

    private func actionButton(_ title: String, isPrimary: Bool) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 12)
        if isPrimary { b.keyEquivalent = "" }
        return b
    }

    // MARK: - Data

    private func loadWebhooks() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            webhooks = []; reloadList(); return
        }
        webhooks = json["webhooks"] as? [[String: Any]] ?? []
        reloadList()
    }

    private func save() {
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        json["webhooks"] = webhooks
        guard let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: out, encoding: .utf8) else { return }
        try? pretty.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func reloadList() {
        endpointTable.reloadData()
        if selectedRow >= webhooks.count { selectedRow = -1 }
        updateDetail()
    }

    private func updateDetail() {
        guard selectedRow >= 0, selectedRow < webhooks.count else {
            detailBox.isHidden = true
            emptyDetail.isHidden = false
            return
        }
        detailBox.isHidden = false
        emptyDetail.isHidden = true

        let hook = webhooks[selectedRow]
        urlField.stringValue    = hook["url"] as? String ?? ""
        enabledCheck.state      = (hook["enabled"] as? Bool ?? true) ? .on : .off
        let routes = (hook["routes"] as? [[String: Any]])?.count ?? 0
        routesLabel.stringValue = "\(routes) route\(routes == 1 ? "" : "s")"

        refreshDeliveryStatus()
        historyTable.reloadData()
        let url = hook["url"] as? String ?? ""
        let forThisHook = deliveryLog.filter { $0.webhookURL == url }
        historyStatus.isHidden = !forThisHook.isEmpty
        revalidateURLField(allowEmpty: false)
    }

    private func refreshDeliveryStatus() {
        guard selectedRow >= 0, selectedRow < webhooks.count,
              let url = webhooks[selectedRow]["url"] as? String,
              let last = deliveryLog.first(where: { $0.webhookURL == url }) else {
            deliveryStatus.stringValue = "No deliveries recorded yet"
            deliveryStatus.textColor   = .secondaryLabelColor
            return
        }
        if let code = last.statusCode {
            let ok = (200...299).contains(code)
            deliveryStatus.stringValue = ok ? "Last delivery: ✓ \(code)" : "Last delivery: ✗ \(code)"
            deliveryStatus.textColor   = ok ? .systemGreen : .systemOrange
        } else if let err = last.errorDescription {
            deliveryStatus.stringValue = "Last delivery failed: \(err)"
            deliveryStatus.textColor   = .systemRed
        }
    }

    // MARK: - Table delegate / data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === endpointTable { return webhooks.count }
        guard selectedRow >= 0, selectedRow < webhooks.count,
              let url = webhooks[selectedRow]["url"] as? String else { return 0 }
        return deliveryLog.filter { $0.webhookURL == url }.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === endpointTable {
            let id   = NSUserInterfaceItemIdentifier("ep")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? EndpointCellView)
                        ?? EndpointCellView(frame: .zero)
            cell.identifier = id
            cell.configure(with: webhooks[row])
            return cell
        } else {
            let id   = NSUserInterfaceItemIdentifier("del")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? DeliveryCellView)
                        ?? DeliveryCellView(frame: .zero)
            cell.identifier = id
            guard selectedRow >= 0, selectedRow < webhooks.count,
                  let url = webhooks[selectedRow]["url"] as? String else { return nil }
            let records = deliveryLog.filter { $0.webhookURL == url }
            if row < records.count { cell.configure(with: records[row]) }
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView, tv === endpointTable else { return }
        selectedRow = endpointTable.selectedRow
    }

    // MARK: - Notification

    @objc private func deliveryRecorded(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String else { return }
        deliveryLog = deliveryStore.load()
        // Refresh if currently viewing this URL or showing history
        if selectedRow >= 0, selectedRow < webhooks.count,
           webhooks[selectedRow]["url"] as? String == url {
            refreshDeliveryStatus()
            historyTable.reloadData()
            historyStatus.isHidden = !deliveryLog.contains(where: { $0.webhookURL == url })
        }
    }

    // MARK: - Actions

    @objc private func saveChanges() {
        guard selectedRow >= 0, selectedRow < webhooks.count else { return }
        switch WebhookURLValidator.validate(urlField.stringValue) {
        case .failure(let err):
            showURLValidation(err)
            urlField.window?.makeFirstResponder(urlField)
            NSSound.beep()
            return
        case .success(let url):
            hideURLValidation()
            webhooks[selectedRow]["url"]     = url.absoluteString
            webhooks[selectedRow]["enabled"] = enabledCheck.state == .on
            reloadList()
            endpointTable.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
            save()
        }
    }

    // MARK: - URL validation feedback

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === urlField else { return }
        revalidateURLField(allowEmpty: true)
    }

    private func revalidateURLField(allowEmpty: Bool) {
        let trimmed = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && allowEmpty {
            hideURLValidation()
            saveBtn?.isEnabled = false
            return
        }
        switch WebhookURLValidator.validate(urlField.stringValue) {
        case .failure(let err):
            showURLValidation(err)
            saveBtn?.isEnabled = false
        case .success:
            hideURLValidation()
            saveBtn?.isEnabled = true
        }
    }

    private func showURLValidation(_ error: WebhookURLError) {
        urlValidationLabel?.stringValue = error.message
        urlValidationLabel?.isHidden = false
    }

    private func hideURLValidation() {
        urlValidationLabel?.isHidden = true
        urlValidationLabel?.stringValue = ""
    }

    @objc private func deleteSelected() {
        guard selectedRow >= 0, selectedRow < webhooks.count, let window else { return }
        let alert = NSAlert()
        alert.messageText  = "Delete webhook?"
        alert.informativeText = webhooks[selectedRow]["url"] as? String ?? ""
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            self.webhooks.remove(at: self.selectedRow)
            self.selectedRow = -1
            self.reloadList()
            self.save()
        }
    }

    @objc private func openEndpoint() {
        guard selectedRow >= 0, selectedRow < webhooks.count,
              let urlStr = webhooks[selectedRow]["url"] as? String,
              let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func sendTest() {
        guard selectedRow >= 0, selectedRow < webhooks.count,
              let urlStr = webhooks[selectedRow]["url"] as? String,
              let url = URL(string: urlStr) else { return }

        deliveryStatus.stringValue = "Sending test payload…"
        deliveryStatus.textColor   = .secondaryLabelColor

        let payload: [String: Any] = [
            "text": "/test",
            "sender": ["handle": "test@example.com", "name": "Test"],
            "chat": ["chatIdentifier": "test@example.com", "name": "Test Chat"],
            "isFromMe": false,
            "date": ISO8601DateFormatter().string(from: Date()),
            "_jared_test": true,
        ]
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.deliveryStatus.stringValue = "Error: \(error.localizedDescription)"
                    self.deliveryStatus.textColor   = .systemRed
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(code) {
                    self.deliveryStatus.stringValue = "Test delivered ✓ \(code)"
                    self.deliveryStatus.textColor   = .systemGreen
                } else {
                    self.deliveryStatus.stringValue = "Test failed ✗ HTTP \(code)"
                    self.deliveryStatus.textColor   = .systemOrange
                }
            }
        }.resume()
    }

    @objc private func rotateHMACSecret() {
        guard selectedRow >= 0, selectedRow < webhooks.count,
              let urlStr = webhooks[selectedRow]["url"] as? String,
              let window else { return }

        let alert = NSAlert()
        alert.messageText = "Rotate HMAC Secret"
        alert.informativeText = "Enter a new shared secret for this webhook, or leave blank to remove the existing secret from Keychain."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        field.placeholderString = "New secret (blank to delete)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let keychain = KeychainStore()
            let newSecret = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if newSecret.isEmpty {
                keychain.delete(for: urlStr)
                self.deliveryStatus.stringValue = "HMAC secret removed from Keychain"
                self.deliveryStatus.textColor   = .secondaryLabelColor
            } else {
                keychain.save(secret: newSecret, for: urlStr)
                self.deliveryStatus.stringValue = "HMAC secret updated in Keychain ✓"
                self.deliveryStatus.textColor   = .systemGreen
            }
        }
    }

    @objc private func addWebhook() {
        let alert = NSAlert()
        alert.messageText = "Add Webhook"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let urlField = NSTextField(frame: NSRect(x: 0, y: 34, width: 400, height: 22))
        urlField.placeholderString = "https://example.com/webhook"

        let modeLabel = NSTextField(labelWithString: "Mode:")
        modeLabel.frame = NSRect(x: 0, y: 4, width: 42, height: 22)

        let modeBtn = NSPopUpButton(frame: NSRect(x: 48, y: 2, width: 130, height: 26))
        modeBtn.addItem(withTitle: "notify")
        modeBtn.addItem(withTitle: "command")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 60))
        container.addSubview(urlField); container.addSubview(modeLabel); container.addSubview(modeBtn)
        alert.accessoryView = container

        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            switch WebhookURLValidator.validate(urlField.stringValue) {
            case .failure(let err):
                let invalid = NSAlert()
                invalid.messageText  = "Invalid webhook URL"
                invalid.informativeText = err.message
                invalid.alertStyle = .warning
                invalid.addButton(withTitle: "OK")
                invalid.beginSheetModal(for: window) { _ in
                    // Re-open the add dialog so the user can correct the input
                    self.addWebhook()
                }
            case .success(let url):
                let mode = modeBtn.selectedItem?.title ?? "notify"
                self.webhooks.append(["url": url.absoluteString, "mode": mode, "enabled": true])
                self.reloadList()
                self.save()
                let last = self.webhooks.count - 1
                self.endpointTable.selectRowIndexes(IndexSet(integer: last), byExtendingSelection: false)
                self.endpointTable.scrollRowToVisible(last)
                self.selectedRow = last
            }
        }
    }

    @objc private func refresh(_ sender: Any) { loadWebhooks() }

    @objc private func closeWindow() { window?.close() }
}
