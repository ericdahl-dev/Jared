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
        databaseHandler = nil
        helper = nil
        router = nil
        testDatabaseLocation = nil
    }
    
    
    func testHandle() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)

        let localRouter = MockRouter()
        var handler: DatabaseHandler? = DatabaseHandler(router: localRouter, databaseLocation: tempDatabaseURL, diskAccessDelegate: nil, enableBackgroundPolling: false, contactNameResolver: { _ in nil })
        var localHelper: DatabaseTestHelper? = DatabaseTestHelper(databaseLocation: tempDatabaseURL)
        defer {
            handler = nil
            localHelper = nil
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        do {
            guard let helper = localHelper else {
                XCTFail("Expected test database helper")
                return
            }

            let handleID = helper.insertHandle(id: "zeke", service: "iMessage")
            let chatID = helper.insertChat(accountId: "zeke", service: "iMessage")
            helper.linkChatAndHandle(chatID: chatID, handleID: handleID)
            
            let timestamp = currentTimestamp()
            let messageID = helper.insertMessage(guid: "lol", messageText: "hello world", handleID: handleID, service: "iMessage", account: "zeke", accountGuid: "String", date: timestamp, dateRead: nil, dateDelivered: nil, isFromMe: false, hasAttachments: false, destinationCallerID: "zeke")
            helper.linkChatAndMessage(chatID: chatID, messageID: messageID, date: timestamp)
            
            let timestamp2 = currentTimestamp()
            let messageID2 = helper.insertMessage(guid: "lol2", messageText: "hello world", handleID: handleID, service: "iMessage", account: "zeke", accountGuid: "String", date: timestamp2, dateRead: nil, dateDelivered: nil, isFromMe: false, hasAttachments: true, destinationCallerID: "zeke")
            helper.linkChatAndMessage(chatID: chatID, messageID: messageID2, date: timestamp2)
            let attachmentID = helper.insertAttachment(guid: "qq", createdAt: timestamp2, filePath: "~/fdsf", mimeType: "image/jpeg", isOutgoing: true, transferName: "hello.jpg", isSticker: false)
            helper.linkAttachmentAndMessage(messageID: messageID2, attachmentID: attachmentID)
        }
        
        _ = handler?.queryNewRecords()
        
        XCTAssertEqual(localRouter.messages.count, 2, "Both messages routed")
    }

    func testIncomingMessageWithMissingHandleDoesNotUseDestinationCallerIdAsSender() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)
        try Self.enableWAL(at: tempDatabaseURL)

        let localRouter = MockRouter()
        var handler: DatabaseHandler? = DatabaseHandler(
            router: localRouter,
            databaseLocation: tempDatabaseURL,
            diskAccessDelegate: nil,
            enableBackgroundPolling: false,
            contactNameResolver: { _ in nil }
        )
        let localHelper = DatabaseTestHelper(databaseLocation: tempDatabaseURL)
        defer {
            handler = nil
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let localPhone = "+18473125379"
        let chatID = localHelper.insertChat(accountId: localPhone, service: "iMessage")
        let timestamp = currentTimestamp()
        let messageID = localHelper.insertMessage(
            guid: "missing-handle",
            messageText: "Cool",
            handleID: 99999,
            service: "iMessage",
            account: localPhone,
            accountGuid: "account-guid",
            date: timestamp,
            dateRead: nil,
            dateDelivered: nil,
            isFromMe: false,
            hasAttachments: false,
            destinationCallerID: localPhone
        )
        localHelper.linkChatAndMessage(chatID: chatID, messageID: messageID, date: timestamp)

        _ = handler?.queryNewRecords()

        XCTAssertEqual(localRouter.messages.count, 0, "Incoming message without sender handle should be skipped")
    }

    func testIncomingOneToOneMessageUsesRemoteHandleNotLocalDestination() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)
        try Self.enableWAL(at: tempDatabaseURL)

        let localRouter = MockRouter()
        var handler: DatabaseHandler? = DatabaseHandler(
            router: localRouter,
            databaseLocation: tempDatabaseURL,
            diskAccessDelegate: nil,
            enableBackgroundPolling: false,
            contactNameResolver: { _ in nil }
        )
        let localHelper = DatabaseTestHelper(databaseLocation: tempDatabaseURL)
        defer {
            handler = nil
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let localPhone = "+18473125379"
        let remotePhone = "+18606558466"
        let remoteHandleID = localHelper.insertHandle(id: remotePhone, service: "iMessage")
        let chatID = localHelper.insertChat(accountId: localPhone, service: "iMessage")
        localHelper.linkChatAndHandle(chatID: chatID, handleID: remoteHandleID)

        let timestamp = currentTimestamp()
        let messageID = localHelper.insertMessage(
            guid: "27EAF9AF-2134-431A-A3E7-BC758959DD88",
            messageText: "Cool",
            handleID: remoteHandleID,
            service: "iMessage",
            account: localPhone,
            accountGuid: "account-guid",
            date: timestamp,
            dateRead: nil,
            dateDelivered: nil,
            isFromMe: false,
            hasAttachments: false,
            destinationCallerID: localPhone,
            cacheRoomNamesNull: true
        )
        localHelper.linkChatAndMessage(chatID: chatID, messageID: messageID, date: timestamp)

        _ = handler?.queryNewRecords()

        XCTAssertEqual(localRouter.messages.count, 1)
        let message = try XCTUnwrap(localRouter.messages.first)
        let sender = try XCTUnwrap(message.sender as? Person)
        let recipient = try XCTUnwrap(message.recipient as? Person)
        XCTAssertEqual(sender.handle, remotePhone)
        XCTAssertFalse(sender.isMe)
        XCTAssertEqual(recipient.handle, localPhone)
        XCTAssertTrue(recipient.isMe)
        XCTAssertNotEqual(sender.handle, recipient.handle)
    }

    func testIncomingMessageDefersUntilHandleIdIsLinked() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)
        try Self.enableWAL(at: tempDatabaseURL)

        let localRouter = MockRouter()
        var handler: DatabaseHandler? = DatabaseHandler(
            router: localRouter,
            databaseLocation: tempDatabaseURL,
            diskAccessDelegate: nil,
            enableBackgroundPolling: false,
            contactNameResolver: { _ in nil }
        )
        let localHelper = DatabaseTestHelper(databaseLocation: tempDatabaseURL)
        defer {
            handler = nil
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let localPhone = "+18473125379"
        let remotePhone = "+18606558466"
        let remoteHandleID = localHelper.insertHandle(id: remotePhone, service: "iMessage")
        let chatID = localHelper.insertChat(accountId: localPhone, service: "iMessage")
        localHelper.linkChatAndHandle(chatID: chatID, handleID: remoteHandleID)

        let timestamp = currentTimestamp()
        let messageID = localHelper.insertMessage(
            guid: "deferred-handle-link",
            messageText: "Hello",
            handleID: 0,
            service: "iMessage",
            account: localPhone,
            accountGuid: "account-guid",
            date: timestamp,
            dateRead: nil,
            dateDelivered: nil,
            isFromMe: false,
            hasAttachments: false,
            destinationCallerID: localPhone,
            cacheRoomNamesNull: true
        )
        localHelper.linkChatAndMessage(chatID: chatID, messageID: messageID, date: timestamp)

        _ = handler?.queryNewRecords()
        XCTAssertEqual(localRouter.messages.count, 0, "Should defer instead of using destination_caller_id as sender")

        localHelper.updateMessageHandleId(messageID: messageID, handleID: remoteHandleID)

        _ = handler?.queryNewRecords()

        XCTAssertEqual(localRouter.messages.count, 1)
        let message = try XCTUnwrap(localRouter.messages.first)
        let sender = try XCTUnwrap(message.sender as? Person)
        let recipient = try XCTUnwrap(message.recipient as? Person)
        XCTAssertEqual(sender.handle, remotePhone)
        XCTAssertFalse(sender.isMe)
        XCTAssertEqual(recipient.handle, localPhone)
        XCTAssertTrue(recipient.isMe)
    }

    func testSelfChatMessageWithNullHandleRoutesUsingDestinationCallerId() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)
        try Self.enableWAL(at: tempDatabaseURL)

        let localRouter = MockRouter()
        var handler: DatabaseHandler? = DatabaseHandler(
            router: localRouter,
            databaseLocation: tempDatabaseURL,
            diskAccessDelegate: nil,
            enableBackgroundPolling: false,
            contactNameResolver: { _ in nil }
        )
        let localHelper = DatabaseTestHelper(databaseLocation: tempDatabaseURL)
        defer {
            handler = nil
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let localPhone = "+18473125379"
        let chatID = localHelper.insertChat(accountId: localPhone, service: "iMessage")
        let timestamp = currentTimestamp()
        let messageID = localHelper.insertMessage(
            guid: "self-chat-null-handle",
            messageText: "note to self",
            handleID: 0,
            service: "iMessage",
            account: localPhone,
            accountGuid: "account-guid",
            date: timestamp,
            dateRead: nil,
            dateDelivered: nil,
            isFromMe: false,
            hasAttachments: false,
            destinationCallerID: localPhone,
            cacheRoomNamesNull: true,
            nullHandleID: true
        )
        localHelper.linkChatAndMessage(chatID: chatID, messageID: messageID, date: timestamp)

        _ = handler?.queryNewRecords()
        XCTAssertEqual(localRouter.messages.count, 0, "Self-chat defers one poll while handle_id is unset")

        _ = handler?.queryNewRecords()

        XCTAssertEqual(localRouter.messages.count, 1)
        let message = try XCTUnwrap(localRouter.messages.first)
        let sender = try XCTUnwrap(message.sender as? Person)
        let recipient = try XCTUnwrap(message.recipient as? Person)
        XCTAssertEqual(sender.handle, localPhone)
        XCTAssertEqual(recipient.handle, localPhone)
    }

    func testOutgoingMessageRoutesWithSenderIsMe() throws {
        let tempDirectory = try makeTemporaryDatabaseDirectory()
        let tempDatabaseURL = tempDirectory.appendingPathComponent("scaffold.db")
        try FileManager.default.copyItem(at: testDatabaseLocation, to: tempDatabaseURL)
        try Self.enableWAL(at: tempDatabaseURL)

        let localRouter = MockRouter()
        var handler: DatabaseHandler? = DatabaseHandler(
            router: localRouter,
            databaseLocation: tempDatabaseURL,
            diskAccessDelegate: nil,
            enableBackgroundPolling: false,
            contactNameResolver: { _ in nil }
        )
        let localHelper = DatabaseTestHelper(databaseLocation: tempDatabaseURL)
        defer {
            handler = nil
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let localPhone = "+18473125379"
        let remotePhone = "+18606558466"
        let remoteHandleID = localHelper.insertHandle(id: remotePhone, service: "iMessage")
        let chatID = localHelper.insertChat(accountId: localPhone, service: "iMessage")
        localHelper.linkChatAndHandle(chatID: chatID, handleID: remoteHandleID)
        let timestamp = currentTimestamp()
        let messageID = localHelper.insertMessage(
            guid: "outbound-message",
            messageText: "sent from mac",
            handleID: remoteHandleID,
            service: "iMessage",
            account: localPhone,
            accountGuid: "account-guid",
            date: timestamp,
            dateRead: nil,
            dateDelivered: nil,
            isFromMe: true,
            hasAttachments: false,
            destinationCallerID: localPhone
        )
        localHelper.linkChatAndMessage(chatID: chatID, messageID: messageID, date: timestamp)

        _ = handler?.queryNewRecords()

        XCTAssertEqual(localRouter.messages.count, 1)
        let message = try XCTUnwrap(localRouter.messages.first)
        let sender = try XCTUnwrap(message.sender as? Person)
        let recipient = try XCTUnwrap(message.recipient as? Person)
        XCTAssertTrue(sender.isMe)
        XCTAssertEqual(sender.handle, localPhone)
        XCTAssertFalse(recipient.isMe)
        XCTAssertEqual(recipient.handle, remotePhone)
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
            throw NSError(domain: "DatabaseHandlerTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open test database"])
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "DatabaseHandlerTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not enable WAL"])
        }
    }

}
