//
//  LLMSettingsViewController.swift
//  JaredUI
//

import Cocoa

final class LLMSettingsViewController: NSViewController {

    // MARK: - Fields

    private let apiKeyField     = NSSecureTextField()
    private let modelField      = NSTextField()
    private let systemField     = NSTextField()
    private let rateLimitField  = NSTextField()

    private let configURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Jared/config.json")
    }()

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        loadValues()
    }

    // MARK: - Build UI

    private func buildUI() {
        let titleLabel = makeLabel("LLM Settings", size: 14, weight: .semibold)
        let subtitleLabel = makeLabel("Jared will forward non-command messages to this LLM.", size: 12, weight: .regular, color: .secondaryLabelColor)

        let apiKeyLabel    = makeLabel("API Key",       size: 12, weight: .medium)
        let modelLabel     = makeLabel("Model",         size: 12, weight: .medium)
        let systemLabel    = makeLabel("System Prompt", size: 12, weight: .medium)
        let rateLimitLabel = makeLabel("Rate Limit (s)", size: 12, weight: .medium)

        for field in [apiKeyField, modelField, systemField, rateLimitField] as [NSTextField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.bezelStyle = .roundedBezel
        }
        modelField.placeholderString      = "gpt-4o"
        systemField.placeholderString     = "You are a helpful assistant."
        rateLimitField.placeholderString  = "10"

        let saveBtn   = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        let docsBtn = NSButton(title: "View docs", target: self, action: #selector(openDocs(_:)))
        docsBtn.bezelStyle = .inline
        docsBtn.font = .systemFont(ofSize: 11)
        docsBtn.contentTintColor = .controlAccentColor
        docsBtn.translatesAutoresizingMaskIntoConstraints = false

        let rows: [(NSView, NSView)] = [
            (apiKeyLabel, apiKeyField),
            (modelLabel,  modelField),
            (systemLabel, systemField),
            (rateLimitLabel, rateLimitField),
        ]

        let labelWidth: CGFloat = 110
        var top: CGFloat = 260

        for (lbl, field) in rows {
            view.addSubview(lbl)
            view.addSubview(field)
            NSLayoutConstraint.activate([
                lbl.trailingAnchor.constraint(equalTo: field.leadingAnchor, constant: -8),
                lbl.centerYAnchor.constraint(equalTo: field.centerYAnchor),
                lbl.widthAnchor.constraint(equalToConstant: labelWidth),
                lbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                field.topAnchor.constraint(equalTo: view.topAnchor, constant: top - 24),
                field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
            top -= 44
        }

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(saveBtn)
        view.addSubview(cancelBtn)
        view.addSubview(docsBtn)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            saveBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            saveBtn.widthAnchor.constraint(equalToConstant: 80),

            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            cancelBtn.centerYAnchor.constraint(equalTo: saveBtn.centerYAnchor),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80),

            docsBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            docsBtn.centerYAnchor.constraint(equalTo: saveBtn.centerYAnchor),
        ])
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }

    // MARK: - Load / Save

    private func loadValues() {
        guard let llm = readLLMBlock() else { return }
        apiKeyField.stringValue    = llm["apiKey"]        as? String ?? ""
        modelField.stringValue     = llm["model"]         as? String ?? ""
        systemField.stringValue    = llm["systemPrompt"]  as? String ?? ""
        if let rate = llm["rateLimitSeconds"] as? Double {
            rateLimitField.stringValue = String(rate)
        }
    }

    @objc private func save(_ sender: Any) {
        var top: [String: Any] = readTopLevel() ?? [:]
        var llm: [String: Any] = top["llm"] as? [String: Any] ?? [:]

        llm["provider"]         = "openai"
        llm["apiKey"]           = apiKeyField.stringValue
        llm["model"]            = modelField.stringValue.isEmpty ? "gpt-4o" : modelField.stringValue
        llm["systemPrompt"]     = systemField.stringValue.isEmpty ? "You are a helpful assistant." : systemField.stringValue
        llm["rateLimitSeconds"] = Double(rateLimitField.stringValue) ?? 10.0
        top["llm"] = llm

        do {
            let data = try JSONSerialization.data(withJSONObject: top, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: configURL, options: .atomic)
        } catch {
            showError(error.localizedDescription)
            return
        }

        dismiss(self)
    }

    @objc private func cancel(_ sender: Any) {
        dismiss(self)
    }

    @objc private func openDocs(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/ericdahl-dev/Jared/blob/master/Documentation/llm.md")!)
    }

    // MARK: - Helpers

    private func readTopLevel() -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    private func readLLMBlock() -> [String: Any]? {
        return readTopLevel()?["llm"] as? [String: Any]
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Failed to save settings"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}
