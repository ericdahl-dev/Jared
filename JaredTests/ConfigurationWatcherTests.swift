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
        {"routes":{},"webhooks":[],"webServer":{"port":3000}}
        """
        try initial.write(to: configURL, atomically: true, encoding: .utf8)

        let expectation = XCTestExpectation(description: "reload callback fired")
        let watcher = ConfigurationWatcher(configURL: configURL) {
            expectation.fulfill()
        }
        watcher.start()

        let updated = """
        {"routes":{"ping":{"disabled":true}},"webhooks":[],"webServer":{"port":3000}}
        """
        try updated.write(to: configURL, atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 3.0)
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
