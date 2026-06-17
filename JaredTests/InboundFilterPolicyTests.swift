//
//  InboundFilterPolicyTests.swift
//  JaredTests
//

import XCTest
import JaredFramework
@testable import Jared

private struct NonTextBody: MessageBody {}

class InboundFilterPolicyTests: XCTestCase {
    private let me = Person(givenName: "me", handle: "me@email.com", isMe: true)
    private let other = Person(givenName: "taylor", handle: "taylor@swift.org", isMe: false)

    private func policy(disabled: Bool = false) -> InboundFilterPolicy {
        InboundFilterPolicy(flags: StubRuntimeFlags(isDisabled: disabled))
    }

    private func textMessage(_ text: String, from sender: Person) -> Message {
        Message(body: TextBody(text), date: Date(), sender: sender, recipient: me)
    }

    func testAllowsNormalIncomingTextMessage() {
        let message = textMessage("/ping", from: other)
        XCTAssertTrue(policy().shouldRoute(message))
    }

    func testBlocksSelfMessage() {
        let message = textMessage("/ping", from: me)
        XCTAssertFalse(policy().shouldRoute(message))
    }

    func testBlocksNonTextNonActionBody() {
        let message = Message(body: NonTextBody(), date: Date(), sender: other, recipient: me)
        XCTAssertFalse(policy().shouldRoute(message))
    }

    func testBlocksWhenDisabled() {
        let message = textMessage("/ping", from: other)
        XCTAssertFalse(policy(disabled: true).shouldRoute(message))
    }

    func testAllowsEnableCommandWhenDisabled() {
        XCTAssertTrue(policy(disabled: true).shouldRoute(textMessage("/enable", from: other)))
    }

    func testEnableBypassIsCaseInsensitive() {
        XCTAssertTrue(policy(disabled: true).shouldRoute(textMessage("/ENABLE", from: other)))
    }

    func testAllowsReactionWithNonTextBody() {
        let reaction = Message(body: NonTextBody(), date: Date(), sender: other, recipient: me,
                               associatedMessageType: 2000, associatedMessageGUID: "p:0/some-guid")
        XCTAssertNotNil(reaction.action)
        XCTAssertTrue(policy().shouldRoute(reaction))
    }
}

class UserDefaultsRuntimeFlagsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "UserDefaultsRuntimeFlagsTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testIsDisabledTrueWhenKeySet() {
        defaults.set(true, forKey: JaredConstants.jaredIsDisabled)
        XCTAssertTrue(UserDefaultsRuntimeFlags(defaults: defaults).isDisabled)
    }

    func testIsDisabledFalseWhenKeyUnset() {
        XCTAssertFalse(UserDefaultsRuntimeFlags(defaults: defaults).isDisabled)
    }
}
