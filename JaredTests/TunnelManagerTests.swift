import XCTest
@testable import Jared

final class MockTunnelRunner: TunnelRunner {
    var isRunning = false
    var lastCommand: TunnelLaunchCommand?
    var startCallCount = 0
    var stopCallCount = 0
    var onOutput: ((String) -> Void)?

    func start(command: TunnelLaunchCommand, onOutput: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void) {
        startCallCount += 1
        lastCommand = command
        self.onOutput = onOutput
        isRunning = true
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
        onOutput = nil
    }
}

class TunnelManagerTests: XCTestCase {

    func testParseCloudflaredURLFromLogLine() {
        let line = "|  https://abc-def.trycloudflare.com                                                    |"
        XCTAssertEqual(
            TunnelURLParser.parsePublicURL(from: line)?.absoluteString,
            "https://abc-def.trycloudflare.com"
        )
    }

    func testParseNgrokURLFromLogLine() {
        let line = "url=https://abc.ngrok-free.app"
        XCTAssertEqual(
            TunnelURLParser.parsePublicURL(from: line)?.absoluteString,
            "https://abc.ngrok-free.app"
        )
    }

    func testSyncDoesNotStartWhenTunnelDisabled() {
        let runner = MockTunnelRunner()
        let manager = TunnelManager(
            configuration: TunnelConfiguration(enabled: false),
            runner: runner,
            keychain: MockKeychain(),
            localPortProvider: { 3005 }
        )

        manager.sync(restApiEnabled: true, localPort: 3005)

        XCTAssertEqual(runner.startCallCount, 0)
        XCTAssertNil(manager.publicURL)
    }

    func testSyncStartsCloudflaredWhenEnabled() {
        let runner = MockTunnelRunner()
        let manager = TunnelManager(
            configuration: TunnelConfiguration(enabled: true, provider: .cloudflared),
            runner: runner,
            keychain: MockKeychain(),
            localPortProvider: { 3005 }
        )

        manager.sync(restApiEnabled: true, localPort: 3005)

        XCTAssertEqual(runner.startCallCount, 1)
        XCTAssertEqual(runner.lastCommand, .cloudflared(localPort: 3005))
    }

    func testOutputLineSetsPublicURL() {
        let runner = MockTunnelRunner()
        let manager = TunnelManager(
            configuration: TunnelConfiguration(enabled: true),
            runner: runner,
            keychain: MockKeychain(),
            localPortProvider: { 3005 }
        )
        let expectation = expectation(forNotification: TunnelManager.publicURLDidChangeNotification, object: manager)

        manager.sync(restApiEnabled: true, localPort: 3005)
        runner.onOutput?("|  https://abc-def.trycloudflare.com  |")

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(manager.publicURL?.absoluteString, "https://abc-def.trycloudflare.com")
    }

    func testStopClearsPublicURL() {
        let runner = MockTunnelRunner()
        let manager = TunnelManager(
            configuration: TunnelConfiguration(enabled: true),
            runner: runner,
            keychain: MockKeychain(),
            localPortProvider: { 3005 }
        )

        manager.sync(restApiEnabled: true, localPort: 3005)
        runner.onOutput?("https://abc-def.trycloudflare.com")
        XCTAssertNotNil(manager.publicURL)

        manager.stop()

        XCTAssertNil(manager.publicURL)
        XCTAssertEqual(runner.stopCallCount, 1)
        XCTAssertFalse(runner.isRunning)
    }

    func testSyncStopsTunnelWhenRestApiDisabled() {
        let runner = MockTunnelRunner()
        let manager = TunnelManager(
            configuration: TunnelConfiguration(enabled: true),
            runner: runner,
            keychain: MockKeychain(),
            localPortProvider: { 3005 }
        )

        manager.sync(restApiEnabled: true, localPort: 3005)
        runner.onOutput?("https://abc-def.trycloudflare.com")
        manager.sync(restApiEnabled: false, localPort: 3005)

        XCTAssertNil(manager.publicURL)
        XCTAssertGreaterThanOrEqual(runner.stopCallCount, 1)
    }

    func testReconfigureStartsTunnelWithNewConfig() {
        let runner = MockTunnelRunner()
        let manager = TunnelManager(
            configuration: TunnelConfiguration(enabled: false),
            runner: runner,
            keychain: MockKeychain(),
            localPortProvider: { 3005 }
        )
        let defaults = UserDefaults(suiteName: #function)!
        defaults.set(false, forKey: JaredConstants.restApiIsDisabled)
        manager.startObserving(defaults: defaults)

        manager.reconfigure(TunnelConfiguration(enabled: true, provider: .cloudflared))

        XCTAssertEqual(runner.startCallCount, 1)
        XCTAssertEqual(runner.lastCommand, .cloudflared(localPort: 3005))
    }

    func testReconfigureStopsRunningTunnel() {
        let runner = MockTunnelRunner()
        let manager = TunnelManager(
            configuration: TunnelConfiguration(enabled: true, provider: .cloudflared),
            runner: runner,
            keychain: MockKeychain(),
            localPortProvider: { 3005 }
        )
        let defaults = UserDefaults(suiteName: #function)!
        defaults.set(false, forKey: JaredConstants.restApiIsDisabled)
        manager.startObserving(defaults: defaults)
        runner.onOutput?("|  https://abc-def.trycloudflare.com  |")

        manager.reconfigure(TunnelConfiguration(enabled: false))

        XCTAssertNil(manager.publicURL)
        XCTAssertFalse(runner.isRunning)
        XCTAssertGreaterThanOrEqual(runner.stopCallCount, 1)
    }

    func testWebserverConfigurationDecodesTunnelBlock() throws {
        let json = """
        {
            "port": 3005,
            "bearerToken": "secret",
            "tunnel": { "enabled": true, "provider": "cloudflared" }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(WebserverConfiguration.self, from: json)

        XCTAssertEqual(config.port, 3005)
        XCTAssertEqual(config.bearerToken, "secret")
        XCTAssertEqual(config.tunnel, TunnelConfiguration(enabled: true, provider: .cloudflared))
    }
}
