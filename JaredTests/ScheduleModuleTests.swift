//
//  ScheduleModuleTests.swift
//  JaredTests
//

import XCTest
import CoreData
import JaredFramework
@testable import Jared

class ScheduleModuleTests: XCTestCase {

    var module: ScheduleModule!
    var mockSender: MockScheduleSender!

    override func setUp() {
        super.setUp()
        mockSender = MockScheduleSender()
        module = ScheduleModule(sender: mockSender, persistentContainer: makeInMemoryContainer())
    }

    override func tearDown() {
        module = nil
        mockSender = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func makeInMemoryContainer() -> PersistentContainer {
        let container = PersistentContainer(name: "CoreModule")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error = error { XCTFail("In-memory store failed: \(error)") }
        }
        return container
    }

    func makeMessage(_ text: String, handle: String = "test-handle") -> Message {
        let person = Person(givenName: "Tester", handle: handle, isMe: false)
        return Message(body: TextBody(text), date: Date(), sender: person, recipient: person)
    }

    // MARK: - Tests

    func testRouteRegistered() {
        XCTAssertTrue(module.routes.contains(where: { $0.name == "/schedule" }))
    }

    func testAddAndListSchedule() {
        module.schedule(makeMessage("/schedule,add,1,Week,2,hello world"))
        XCTAssertTrue(mockSender.sent.last?.contains("scheduled") == true, "Expected confirmation, got: \(mockSender.sent)")

        mockSender.sent.removeAll()
        module.schedule(makeMessage("/schedule,list"))
        let reply = mockSender.sent.last ?? ""
        XCTAssertTrue(reply.contains("1"), "List should mention 1 post, got: \(reply)")
    }

    func testDeleteSchedule() {
        module.schedule(makeMessage("/schedule,add,1,Week,2,hello world"))
        module.schedule(makeMessage("/schedule,delete,1"))
        XCTAssertTrue(mockSender.sent.last?.contains("deleted") == true, "Expected deletion confirm, got: \(mockSender.sent)")

        mockSender.sent.removeAll()
        module.schedule(makeMessage("/schedule,list"))
        let reply = mockSender.sent.last ?? ""
        XCTAssertTrue(reply.contains("0"), "List should show 0 posts after delete, got: \(reply)")
    }
}

// MARK: - MockScheduleSender

class MockScheduleSender: MessageSender {
    var sent: [String] = []
    func send(_ body: String, to recipient: RecipientEntity?) { sent.append(body) }
    func send(_ message: Message) {}
}
