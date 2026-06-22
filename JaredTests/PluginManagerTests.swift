import XCTest
import JaredFramework
@testable import Jared

class PluginManagerTests: XCTestCase {

    private func makeManager(disabledCommands: [String: Bool] = [:]) -> PluginManager {
        let config = ConfigurationFile(disabledCommands: disabledCommands)
        return PluginManager(sender: JaredMock(), configuration: config)
    }

    // MARK: - enabled()

    func testEnabledReturnsTrueWhenCommandNotInMap() {
        XCTAssertTrue(makeManager().enabled(routeName: "/ping"))
    }

    func testEnabledReturnsFalseWhenCommandDisabled() {
        XCTAssertFalse(makeManager(disabledCommands: ["/ping": true]).enabled(routeName: "/ping"))
    }

    func testEnabledReturnsTrueWhenCommandExplicitlyEnabled() {
        XCTAssertTrue(makeManager(disabledCommands: ["/ping": false]).enabled(routeName: "/ping"))
    }

    func testEnabledIsCaseInsensitive() {
        XCTAssertFalse(makeManager(disabledCommands: ["/ping": true]).enabled(routeName: "/PING"))
    }

    // MARK: - getAllModules() / getAllRoutes()

    func testGetAllModulesHasFourInternalModulesOnInit() {
        // CoreModule, ScheduleModule, InternalModule, WebHookManager
        XCTAssertEqual(makeManager().getAllModules().count, 4)
    }

    func testGetAllRoutesIncludesPingRoute() {
        XCTAssertTrue(makeManager().getAllRoutes().contains { $0.name == "/ping" })
    }

    // MARK: - reload()

    func testReloadPreservesModuleCount() {
        let manager = makeManager()
        manager.reload()
        XCTAssertEqual(manager.getAllModules().count, 4)
    }

    func testReloadRestoresPingRoute() {
        let manager = makeManager()
        manager.reload()
        XCTAssertTrue(manager.getAllRoutes().contains { $0.name == "/ping" })
    }

    // MARK: - apply()

    func testApplyUpdatesDisabledCommands() {
        let manager = makeManager()
        XCTAssertTrue(manager.enabled(routeName: "/ping"))

        manager.apply(ConfigurationFile(disabledCommands: ["/ping": true]))

        XCTAssertFalse(manager.enabled(routeName: "/ping"))
    }

    func testApplyUpdatesWebhooks() {
        let manager = makeManager()
        XCTAssertTrue(manager.config.webhooks.isEmpty)

        let hook = RichWebhook(url: "https://example.com")
        manager.apply(ConfigurationFile(webhooks: [hook]))

        XCTAssertEqual(manager.config.webhooks.count, 1)
        XCTAssertEqual(manager.config.webhooks.first?.url, "https://example.com")
    }
}
