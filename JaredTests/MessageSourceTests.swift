//
//  MessageSourceTests.swift
//  JaredTests
//

import XCTest
import JaredFramework
@testable import Jared

class MessageSourceTests: XCTestCase {
    let sender = Person(givenName: "Test", handle: "test-handle", isMe: false)
    let me = Person(givenName: "Me", handle: "me-handle", isMe: true)

    func makeMessage(_ text: String) -> Message {
        Message(body: TextBody(text), date: Date(), sender: sender, recipient: me)
    }

    func testInMemorySourceDeliversMessages() {
        let source = InMemoryMessageSource()
        var received: [Message] = []
        source.onMessage = { received.append($0) }

        let msg = makeMessage("hello")
        source.push(msg)

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual((received.first?.body as? TextBody)?.message, "hello")
    }

    func testInMemorySourceDeliversMultipleMessages() {
        let source = InMemoryMessageSource()
        var received: [Message] = []
        source.onMessage = { received.append($0) }

        source.push(makeMessage("one"))
        source.push(makeMessage("two"))
        source.push(makeMessage("three"))

        XCTAssertEqual(received.count, 3)
    }

    func testInMemorySourceWithNoHandlerDoesNotCrash() {
        let source = InMemoryMessageSource()
        source.push(makeMessage("ignored"))
    }
}
