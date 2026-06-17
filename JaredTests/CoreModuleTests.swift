//
//  CoreModuleTests.swift
//  JaredTests
//

import XCTest
import JaredFramework
@testable import Jared

private struct NonTextBody: MessageBody {}

private struct InstantClock: Clock {
    func sleep(seconds: Int) async {}
}

private final class FakeContactNameService: ContactNameService {
    var isAuthorized: Bool
    var errorToThrow: Error?
    private(set) var saved: [(name: String, handle: String)] = []

    init(isAuthorized: Bool = true, errorToThrow: Error? = nil) {
        self.isAuthorized = isAuthorized
        self.errorToThrow = errorToThrow
    }

    func setGivenName(_ name: String, forHandle handle: String) throws {
        if let errorToThrow { throw errorToThrow }
        saved.append((name, handle))
    }
}

private struct DummyError: Error {}

class CoreModuleTests: XCTestCase {
    private var mock: JaredMock!
    private let me = Person(givenName: "zeke", handle: "zeke@email.com", isMe: true)
    private let other = Person(givenName: "taylor", handle: "taylor@swift.org", isMe: false)

    override func setUp() {
        mock = JaredMock()
    }

    private func module() -> CoreModule {
        CoreModule(sender: mock)
    }

    private func textMessage(_ text: String) -> Message {
        Message(body: TextBody(text), date: Date(), sender: other, recipient: me)
    }

    private func lastReply() -> String? {
        (mock.calls.last?.body as? TextBody)?.message
    }

    func testPingRepliesPong() {
        module().pingCall(textMessage("/ping"))
        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(lastReply(), NSLocalizedString("PongResponse"))
    }

    func testVersionReplies() {
        module().getVersion(textMessage("/version"))
        XCTAssertEqual(lastReply(), NSLocalizedString("versionResponse"))
    }

    func testThanksJaredReplies() {
        module().thanksJared(textMessage("thanks"))
        XCTAssertEqual(lastReply(), NSLocalizedString("WelcomeResponse"))
    }

    func testWhoamiRepliesNameWhenKnown() {
        let msg = Message(body: TextBody("/whoami"), date: Date(),
                          sender: Person(givenName: "Taylor", handle: "t@swift.org", isMe: false),
                          recipient: me)
        module().getWho(msg)
        XCTAssertEqual(lastReply(), "Your name is Taylor.")
    }

    func testWhoamiRepliesUnknownWhenNoName() {
        let msg = Message(body: TextBody("/whoami"), date: Date(),
                          sender: Person(givenName: nil, handle: "t@swift.org", isMe: false),
                          recipient: me)
        module().getWho(msg)
        XCTAssertEqual(lastReply(), "I don't know your name.")
    }

    func testBarfRepliesEncodedMessage() {
        module().barf(textMessage("/barf"))
        XCTAssertEqual(mock.calls.count, 1)
        let reply = lastReply()
        XCTAssertNotNil(reply)
        XCTAssertTrue(reply!.contains("/barf"), "barf echoes encoded message JSON")
    }

    // MARK: - /send validation

    func testSendRejectsNonTextBody() {
        let msg = Message(body: NonTextBody(), date: Date(), sender: other, recipient: me)
        module().sendRepeat(msg)
        XCTAssertEqual(lastReply(), "Inappropriate input type.")
    }

    func testSendRejectsNonNumericCount() {
        module().sendRepeat(textMessage("/send,abc,1,hi"))
        XCTAssertEqual(lastReply(), "Wrong argument. The first argument must be the number of message you wish to send")
    }

    func testSendRejectsNonNumericDelay() {
        module().sendRepeat(textMessage("/send,2,abc,hi"))
        XCTAssertEqual(lastReply(), "Wrong argument. The second argument must be the delay of the messages you wish to send")
    }

    func testSendRejectsMissingText() {
        module().sendRepeat(textMessage("/send,2,1"))
        XCTAssertEqual(lastReply(), "Wrong arguments. The third argument must be the message you wish to send.")
    }

    func testSendDeliversRepeatedMessages() async {
        let mod = CoreModule(sender: mock, clock: InstantClock())
        await mod.performSend(textMessage("/send,3,0,hi"), text: "hi", times: 3)
        XCTAssertEqual(mock.calls.count, 3)
        XCTAssertEqual(lastReply(), "hi")
    }

    func testSendRejectsWhenAtConcurrencyLimit() {
        let limiter = SendRateLimiter(max: 3)
        _ = limiter.tryAcquire(other.handle)
        _ = limiter.tryAcquire(other.handle)
        _ = limiter.tryAcquire(other.handle)
        let mod = CoreModule(sender: mock, clock: InstantClock(), rateLimiter: limiter)

        mod.sendRepeat(textMessage("/send,1,0,hi"))

        XCTAssertEqual(lastReply(), "You can only have 3 send operations going at once.")
    }

    // MARK: - /name

    private func module(contacts: ContactNameService) -> CoreModule {
        CoreModule(sender: mock, contacts: contacts)
    }

    func testNameRepliesWhenNotAuthorized() {
        let mod = module(contacts: FakeContactNameService(isAuthorized: false))
        mod.changeName(textMessage("/name,Taylor"))
        XCTAssertEqual(lastReply(), "Sorry, I do not have access to contacts.")
    }

    func testNameRejectsMissingArgument() {
        let mod = module(contacts: FakeContactNameService())
        mod.changeName(textMessage("/name"))
        XCTAssertEqual(lastReply(), "Wrong arguments.")
    }

    func testNameRejectsNonTextBody() {
        let mod = module(contacts: FakeContactNameService())
        mod.changeName(Message(body: NonTextBody(), date: Date(), sender: other, recipient: me))
        XCTAssertEqual(lastReply(), "Inappropriate input type")
    }

    func testNameSavesGivenNameAndConfirms() {
        let fake = FakeContactNameService()
        let mod = module(contacts: fake)
        mod.changeName(textMessage("/name,Taylor"))
        XCTAssertEqual(fake.saved.count, 1)
        XCTAssertEqual(fake.saved.first?.name, "Taylor")
        XCTAssertEqual(fake.saved.first?.handle, other.handle)
        XCTAssertEqual(lastReply(), "Ok, I'll call you Taylor from now on.")
    }

    func testNameRepliesErrorWhenSaveThrows() {
        let mod = module(contacts: FakeContactNameService(errorToThrow: DummyError()))
        mod.changeName(textMessage("/name,Taylor"))
        XCTAssertEqual(lastReply(), "There was an error saving your contact..")
    }

    // MARK: - init

    func testInitRegistersRoutesWithoutFilesystemSideEffects() {
        let mod = CoreModule(sender: mock)
        XCTAssertFalse(mod.routes.isEmpty)
        XCTAssertTrue(mod.routes.contains { $0.name == "/ping" })
        XCTAssertTrue(mod.routes.contains { $0.name == "/send" })
        XCTAssertTrue(mod.routes.contains { $0.name == "/name" })
    }
}

class SendRateLimiterTests: XCTestCase {
    func testAcquiresUpToMaxThenRejects() {
        let limiter = SendRateLimiter(max: 3)
        XCTAssertTrue(limiter.tryAcquire("a"))
        XCTAssertTrue(limiter.tryAcquire("a"))
        XCTAssertTrue(limiter.tryAcquire("a"))
        XCTAssertFalse(limiter.tryAcquire("a"), "4th concurrent send for same handle is rejected")
    }

    func testReleaseFreesSlot() {
        let limiter = SendRateLimiter(max: 1)
        XCTAssertTrue(limiter.tryAcquire("a"))
        XCTAssertFalse(limiter.tryAcquire("a"))
        limiter.release("a")
        XCTAssertTrue(limiter.tryAcquire("a"), "slot reusable after release")
    }

    func testLimitIsPerHandle() {
        let limiter = SendRateLimiter(max: 1)
        XCTAssertTrue(limiter.tryAcquire("a"))
        XCTAssertTrue(limiter.tryAcquire("b"), "different handle has its own quota")
    }
}
