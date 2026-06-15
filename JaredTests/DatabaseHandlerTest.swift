//
//  MessageTests.swift
//  JaredTests
//
//  Created by Zeke Snider on 2/3/19.
//  Copyright © 2019 Zeke Snider. All rights reserved.
//

import XCTest
@testable import Jared
import JaredFramework
import SQLite3

private final class DiskAccessDelegateSpy: DiskAccessDelegate {
    private(set) var didDisplayAccessError = false

    func displayAccessError() {
        didDisplayAccessError = true
    }
}

class DatabaseHandlerTest: XCTestCase {
    var testDatabaseLocation: URL! = nil
    var helper: DatabaseTestHelper! = nil
    var router: MockRouter! = nil
    var databaseHandler: DatabaseHandler! = nil
    
    private func currentTimestamp() -> Int {
        return Int(Date().timeIntervalSinceReferenceDate * 1000000000)
    }
    
    override func setUp() {
        let bundle = Bundle(for: type(of: self))
        testDatabaseLocation = bundle.url(forResource: "scaffold", withExtension: "db")
        helper = DatabaseTestHelper(databaseLocation: testDatabaseLocation)
        router = MockRouter()
        databaseHandler = DatabaseHandler(router: router, databaseLocation: testDatabaseLocation, diskAccessDelegate: nil)
    }
    
    override func tearDown() {
    }
    
    
    func testHandle() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)
        try Self.enableWAL(at: tempDatabaseURL)

        let localRouter = MockRouter()
        var handler: DatabaseHandler? = DatabaseHandler(router: localRouter, databaseLocation: tempDatabaseURL, diskAccessDelegate: nil, enableBackgroundPolling: false, contactNameResolver: { _ in nil })
        let localHelper = DatabaseTestHelper(databaseLocation: tempDatabaseURL)
        defer {
            handler = nil
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let handleID = localHelper.insertHandle(id: "zeke", service: "iMessage")
        let chatID = localHelper.insertChat(accountId: "zeke", service: "iMessage")
        localHelper.linkChatAndHandle(chatID: chatID, handleID: handleID)
        
        let timestamp = currentTimestamp()
        let messageID = localHelper.insertMessage(guid: "lol", messageText: "hello world", handleID: handleID, service: "iMessage", account: "zeke", accountGuid: "String", date: timestamp, dateRead: nil, dateDelivered: nil, isFromMe: false, hasAttachments: false, destinationCallerID: "zeke")
        localHelper.linkChatAndMessage(chatID: chatID, messageID: messageID, date: timestamp)
        
        let timestamp2 = currentTimestamp()
        let messageID2 = localHelper.insertMessage(guid: "lol2", messageText: "hello world", handleID: handleID, service: "iMessage", account: "zeke", accountGuid: "String", date: timestamp2, dateRead: nil, dateDelivered: nil, isFromMe: false, hasAttachments: true, destinationCallerID: "zeke")
        localHelper.linkChatAndMessage(chatID: chatID, messageID: messageID2, date: timestamp2)
        let attachmentID = localHelper.insertAttachment(guid: "qq", createdAt: timestamp2, filePath: "~/fdsf", mimeType: "image/jpeg", isOutgoing: true, transferName: "hello.jpg", isSticker: false)
        localHelper.linkAttachmentAndMessage(messageID: messageID2, attachmentID: attachmentID)
        
        _ = handler?.queryNewRecords()
        
        XCTAssertEqual(localRouter.messages.count, 2, "Both messages routed")
    }

    func testInitDoesNotCreateMissingWALFile() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)
        let walURL = URL(fileURLWithPath: tempDatabaseURL.path + "-wal")
        try? FileManager.default.removeItem(at: walURL)
        var handler: DatabaseHandler? = nil
        defer {
            handler = nil
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        handler = DatabaseHandler(router: router, databaseLocation: tempDatabaseURL, diskAccessDelegate: nil)
        XCTAssertNotNil(handler)
        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path), "Init should not create a missing WAL file")
    }

    func testInitCanOpenReadOnlyDatabaseWithoutAccessError() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)

        let delegate = DiskAccessDelegateSpy()
        var handler: DatabaseHandler? = nil
        let previousValue = UserDefaults.standard.object(forKey: JaredConstants.fullDiskAccess)
        defer {
            handler = nil
            chmod(tempDirectory.path, 0o755)
            chmod(tempDatabaseURL.path, 0o644)
            try? FileManager.default.removeItem(at: tempDirectory)
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: JaredConstants.fullDiskAccess)
            } else {
                UserDefaults.standard.removeObject(forKey: JaredConstants.fullDiskAccess)
            }
        }

        XCTAssertEqual(chmod(tempDatabaseURL.path, 0o444), 0, "Should make DB read-only")
        XCTAssertEqual(chmod(tempDirectory.path, 0o555), 0, "Should make DB directory non-writable")

        handler = DatabaseHandler(router: router, databaseLocation: tempDatabaseURL, diskAccessDelegate: delegate)

        XCTAssertNotNil(handler)
        XCTAssertFalse(delegate.didDisplayAccessError, "Read-only DB should open without triggering disk access error")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: JaredConstants.fullDiskAccess), "Read-only DB open should mark full disk access as available")
    }

    private func makeTemporaryDatabaseDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func enableWAL(at databaseURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "DatabaseHandlerTest", code: 1)
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "DatabaseHandlerTest", code: 2)
        }
    }
}
