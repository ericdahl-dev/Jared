//
//  MessageMatcherTests.swift
//  JaredTests
//

import XCTest
import JaredFramework
@testable import Jared

class MessageMatcherTests: XCTestCase {
    let matcher = MessageMatcher()
    let sender = Person(givenName: "test", handle: "test@test.com", isMe: false)
    let me = Person(givenName: "me", handle: "me@test.com", isMe: true)

    func makeMessage(_ text: String, action: Action? = nil) -> Message {
        Message(body: TextBody(text), date: Date(), sender: sender, recipient: me, associatedMessageType: action != nil ? 2000 : nil, associatedMessageGUID: action?.targetGUID)
    }

    func makeRoute(_ comparisons: [Compare: [String]]) -> Route {
        Route(name: "test", comparisons: comparisons, call: { _ in })
    }

    // MARK: startsWith

    func testStartsWithMatch() {
        let route = makeRoute([.startsWith: ["/ping"]])
        let msg = makeMessage("/ping hello")
        XCTAssertNotNil(matcher.matchingMessage(route: route, message: msg))
    }

    func testStartsWithNoMatch() {
        let route = makeRoute([.startsWith: ["/ping"]])
        let msg = makeMessage("hello /ping")
        XCTAssertNil(matcher.matchingMessage(route: route, message: msg))
    }

    func testStartsWithCaseInsensitive() {
        let route = makeRoute([.startsWith: ["/PING"]])
        let msg = makeMessage("/ping hello")
        XCTAssertNotNil(matcher.matchingMessage(route: route, message: msg))
    }

    // MARK: contains

    func testContainsMatch() {
        let route = makeRoute([.contains: ["hello"]])
        let msg = makeMessage("say hello world")
        XCTAssertNotNil(matcher.matchingMessage(route: route, message: msg))
    }

    func testContainsNoMatch() {
        let route = makeRoute([.contains: ["hello"]])
        let msg = makeMessage("goodbye world")
        XCTAssertNil(matcher.matchingMessage(route: route, message: msg))
    }

    // MARK: is

    func testIsMatch() {
        let route = makeRoute([.is: ["/help"]])
        let msg = makeMessage("/help")
        XCTAssertNotNil(matcher.matchingMessage(route: route, message: msg))
    }

    func testIsNoMatch() {
        let route = makeRoute([.is: ["/help"]])
        let msg = makeMessage("/help extra")
        XCTAssertNil(matcher.matchingMessage(route: route, message: msg))
    }

    // MARK: containsURL

    func testContainsURLMatch() {
        let route = makeRoute([.containsURL: ["github.com"]])
        let msg = makeMessage("check out https://github.com/foo")
        let result = matcher.matchingMessage(route: route, message: msg)
        XCTAssertNotNil(result)
        // The returned message body should be just the URL
        XCTAssertTrue((result?.body as? TextBody)?.message.contains("github.com") == true)
    }

    func testContainsURLNoMatch() {
        let route = makeRoute([.containsURL: ["github.com"]])
        let msg = makeMessage("no links here")
        XCTAssertNil(matcher.matchingMessage(route: route, message: msg))
    }

    // MARK: isReaction

    func testIsReactionMatch() {
        let action = Action(actionTypeInt: 2000, targetGUID: "abc")
        let route = makeRoute([.isReaction: []])
        let msg = makeMessage("liked a message", action: action)
        XCTAssertNotNil(matcher.matchingMessage(route: route, message: msg))
    }

    func testIsReactionNoMatch() {
        let route = makeRoute([.isReaction: []])
        let msg = makeMessage("normal message")
        XCTAssertNil(matcher.matchingMessage(route: route, message: msg))
    }

    // MARK: non-TextBody

    func testNonTextBodyReturnsNil() {
        let route = makeRoute([.startsWith: ["/ping"]])
        let msg = Message(body: nil, date: Date(), sender: sender, recipient: me)
        XCTAssertNil(matcher.matchingMessage(route: route, message: msg))
    }
}
