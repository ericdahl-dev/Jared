//
//  ConfigurationWatcherTests.swift
//  JaredTests
//

import XCTest
@testable import Jared

class ConfigurationWatcherTests: XCTestCase {

    func testCallbackFiredOnFileWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("config.json")
        let initial = """
        {"webhooks":[],"webServer":{"port":3000}}
        """
        try initial.write(to: configURL, atomically: true, encoding: .utf8)

        let expectation = XCTestExpectation(description: "reload callback fired")
        let watcher = ConfigurationWatcher(configURL: configURL) {
            expectation.fulfill()
        }
        watcher.start()

        let updated = """
        {"disabledCommands":{"/ping":true},"webhooks":[],"webServer":{"port":3000}}
        """
        try updated.write(to: configURL, atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 3.0)
    }

    func testApplierCalledWithParsedConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("config.json")
        let initial = """
        {"webhooks":[],"webServer":{"port":3000}}
        """
        try initial.write(to: configURL, atomically: true, encoding: .utf8)

        class RecordingApplier: ConfigurationApplier {
            var applied: [ConfigurationFile] = []
            func apply(_ newConfig: ConfigurationFile) { applied.append(newConfig) }
        }

        let applier = RecordingApplier()
        let expectation = XCTestExpectation(description: "apply called")
        let watcher = ConfigurationWatcher(configURL: configURL, applier: applier) {
            if !applier.applied.isEmpty { expectation.fulfill() }
        }
        watcher.start()

        let updated = """
        {"webhooks":[],"webServer":{"port":4000}}
        """
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(applier.applied.last?.webServer.port, 4000)
    }

    func testDisabledCommandsNewKey() throws {
        let json = """
        {"disabledCommands":{"/ping":true,"/send":false},"webhooks":[],"webServer":{"port":3000}}
        """
        let config = try JSONDecoder().decode(ConfigurationFile.self, from: Data(json.utf8))
        XCTAssertTrue(config.disabledCommands["/ping"] == true)
        XCTAssertTrue(config.disabledCommands["/send"] == false)
    }

    func testDisabledCommandsLegacyRoutesKey() throws {
        let json = """
        {"routes":{"/ping":{"disabled":true},"/send":{"disabled":false}},"webhooks":[],"webServer":{"port":3000}}
        """
        let config = try JSONDecoder().decode(ConfigurationFile.self, from: Data(json.utf8))
        XCTAssertTrue(config.disabledCommands["/ping"] == true)
        XCTAssertTrue(config.disabledCommands["/send"] == false)
    }

    func testCallbackNotFiredBeforeStart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("config.json")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)

        var called = false
        let watcher = ConfigurationWatcher(configURL: configURL) { called = true }

        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(called)
        _ = watcher
    }
}
