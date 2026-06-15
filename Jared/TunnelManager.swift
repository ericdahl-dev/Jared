import Foundation

// MARK: - Configuration

enum TunnelProvider: String, Decodable, Equatable {
    case cloudflared
    case ngrok
}

struct TunnelConfiguration: Decodable, Equatable {
    let enabled: Bool
    let provider: TunnelProvider

    init(enabled: Bool = false, provider: TunnelProvider = .cloudflared) {
        self.enabled = enabled
        self.provider = provider
    }
}

// MARK: - URL parsing

enum TunnelURLParser {
    private static let pattern = #"https://[a-zA-Z0-9][-a-zA-Z0-9.]*\.(trycloudflare\.com|ngrok-free\.app|ngrok\.io)(?:/[^\s|"]*)?"#

    static func parsePublicURL(from line: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let urlRange = Range(match.range, in: line) else { return nil }
        let trimmed = String(line[urlRange]).trimmingCharacters(in: CharacterSet(charactersIn: "|\"' "))
        return URL(string: trimmed)
    }
}

// MARK: - Process launching

struct TunnelLaunchCommand: Equatable {
    let arguments: [String]
    let environment: [String: String]?

    static func cloudflared(localPort: Int) -> TunnelLaunchCommand {
        TunnelLaunchCommand(
            arguments: ["cloudflared", "tunnel", "--url", "http://127.0.0.1:\(localPort)"],
            environment: nil
        )
    }

    static func ngrok(localPort: Int, authToken: String) -> TunnelLaunchCommand {
        TunnelLaunchCommand(
            arguments: ["ngrok", "http", String(localPort)],
            environment: ["NGROK_AUTHTOKEN": authToken]
        )
    }
}

protocol TunnelRunner: AnyObject {
    var isRunning: Bool { get }
    func start(command: TunnelLaunchCommand, onOutput: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void)
    func stop()
}

enum TunnelError: LocalizedError {
    case processExited(Int32)
    case missingNgrokToken

    var errorDescription: String? {
        switch self {
        case .processExited(let code):
            return "Tunnel process exited with status \(code)"
        case .missingNgrokToken:
            return "ngrok requires an authtoken in Keychain (account: \(TunnelManager.ngrokKeychainAccount))"
        }
    }
}

final class ProcessTunnelRunner: TunnelRunner {
    private var process: Process?

    var isRunning: Bool { process?.isRunning ?? false }

    func start(command: TunnelLaunchCommand, onOutput: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void) {
        stop()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = command.arguments
        if let environment = command.environment {
            var env = ProcessInfo.processInfo.environment
            environment.forEach { env[$0.key] = $0.value }
            proc.environment = env
        }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            text.split(separator: "\n", omittingEmptySubsequences: false).forEach { line in
                onOutput(String(line))
            }
        }

        proc.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            if finished.terminationStatus != 0 {
                onComplete(TunnelError.processExited(finished.terminationStatus))
            } else {
                onComplete(nil)
            }
            self?.process = nil
        }

        do {
            try proc.run()
            process = proc
        } catch {
            onComplete(error)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}

// MARK: - Manager

final class TunnelManager: NSObject {
    static let publicURLDidChangeNotification = Notification.Name("TunnelManagerPublicURLDidChange")
    static let publicURLUserInfoKey = "publicURL"
    static let lastErrorUserInfoKey = "lastError"
    static let ngrokKeychainAccount = "ngrok-authtoken"

    private let configuration: TunnelConfiguration
    private let runner: TunnelRunner
    private let keychain: KeychainAccessor
    private let localPortProvider: () -> Int
    private var defaults: UserDefaults?

    private(set) var publicURL: URL?
    private(set) var lastError: String?

    init(configuration: TunnelConfiguration,
         runner: TunnelRunner = ProcessTunnelRunner(),
         keychain: KeychainAccessor = KeychainStore(),
         localPortProvider: @escaping () -> Int) {
        self.configuration = configuration
        self.runner = runner
        self.keychain = keychain
        self.localPortProvider = localPortProvider
        super.init()
    }

    func startObserving(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.addObserver(self, forKeyPath: JaredConstants.restApiIsDisabled, options: .new, context: nil)
        syncFromDefaults()
    }

    deinit {
        if let defaults {
            defaults.removeObserver(self, forKeyPath: JaredConstants.restApiIsDisabled)
        }
        stop()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == JaredConstants.restApiIsDisabled {
            DispatchQueue.main.async { [weak self] in
                self?.syncFromDefaults()
            }
        }
    }

    func sync(restApiEnabled: Bool, localPort: Int) {
        guard configuration.enabled, restApiEnabled else {
            stop()
            return
        }
        guard !runner.isRunning else { return }

        let command: TunnelLaunchCommand
        switch configuration.provider {
        case .cloudflared:
            command = .cloudflared(localPort: localPort)
        case .ngrok:
            guard let token = keychain.secret(for: Self.ngrokKeychainAccount), !token.isEmpty else {
                setError(TunnelError.missingNgrokToken.localizedDescription)
                return
            }
            command = .ngrok(localPort: localPort, authToken: token)
        }

        runner.start(command: command, onOutput: { [weak self] line in
            self?.handleOutputLine(line)
        }, onComplete: { [weak self] error in
            if let error {
                self?.setError(error.localizedDescription)
            }
        })
    }

    func stop() {
        runner.stop()
        if publicURL != nil {
            publicURL = nil
            postChange()
        }
        lastError = nil
    }

    private func handleOutputLine(_ line: String) {
        guard let url = TunnelURLParser.parsePublicURL(from: line) else { return }
        guard url != publicURL else { return }
        publicURL = url
        lastError = nil
        postChange()
    }

    private func setError(_ message: String) {
        lastError = message
        postChange()
    }

    private func postChange() {
        NotificationCenter.default.post(
            name: Self.publicURLDidChangeNotification,
            object: self,
            userInfo: [
                Self.publicURLUserInfoKey: publicURL as Any,
                Self.lastErrorUserInfoKey: lastError as Any,
            ]
        )
    }

    private func syncFromDefaults() {
        let restDisabled = defaults?.bool(forKey: JaredConstants.restApiIsDisabled) ?? true
        sync(restApiEnabled: !restDisabled, localPort: localPortProvider())
    }
}
