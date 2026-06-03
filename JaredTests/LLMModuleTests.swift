//
//  LLMModuleTests.swift
//  JaredTests
//

import XCTest
import JaredFramework
@testable import Jared

class LLMModuleTests: XCTestCase {
    let sender = JaredMock()
    let testConfig = LLMConfiguration(
        provider: "openai",
        apiKey: "test-key",
        model: "gpt-4o",
        systemPrompt: "You are a helpful assistant.",
        rateLimitSeconds: 1.0
    )
    let me = Person(givenName: "zeke", handle: "zeke@email.com", isMe: true)
    let other = Person(givenName: "taylor", handle: "taylor@swift.org", isMe: false)

    var sessionConfig: URLSessionConfiguration!

    override func setUp() {
        sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [URLProtocolMock.self]
        URLProtocolMock.testURLs = [:]
        URLProtocolMock.matchedDataURLs = []
        sender.calls = []
    }

    func testSendsReplyFromLLMResponse() {
        let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
        let responseJSON = """
        {"choices":[{"message":{"content":"Hello from LLM!"}}]}
        """.data(using: .utf8)!
        URLProtocolMock.testURLs[apiURL] = responseJSON

        let module = LLMModule(sender: sender, config: testConfig, session: URLSession(configuration: sessionConfig))
        let message = Message(body: TextBody("Hi there"), date: Date(), sender: other, recipient: me)

        module.handle(message)
        sleep(2)

        XCTAssertEqual((sender.calls.first?.body as? TextBody)?.message, "Hello from LLM!")
    }

    func testSkipsSlashCommands() {
        let module = LLMModule(sender: sender, config: testConfig, session: URLSession(configuration: sessionConfig))
        let message = Message(body: TextBody("/ping"), date: Date(), sender: other, recipient: me)

        module.handle(message)
        sleep(1)

        XCTAssertTrue(sender.calls.isEmpty, "Should not call LLM for slash commands")
    }

    func testRateLimiting() {
        let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
        let responseJSON = """
        {"choices":[{"message":{"content":"Reply"}}]}
        """.data(using: .utf8)!
        URLProtocolMock.testURLs[apiURL] = responseJSON

        let module = LLMModule(sender: sender, config: testConfig, session: URLSession(configuration: sessionConfig))
        let message = Message(body: TextBody("First"), date: Date(), sender: other, recipient: me)
        let messageTwo = Message(body: TextBody("Second"), date: Date(), sender: other, recipient: me)

        module.handle(message)
        module.handle(messageTwo)
        sleep(2)

        XCTAssertEqual(sender.calls.count, 1, "Second message should be rate-limited")
    }

    func testGracefulAPIFailure() {
        // No URL mock registered = network failure path
        let module = LLMModule(sender: sender, config: testConfig, session: URLSession(configuration: sessionConfig))
        let message = Message(body: TextBody("Hello"), date: Date(), sender: other, recipient: me)

        module.handle(message)
        sleep(2)

        XCTAssertTrue(sender.calls.isEmpty, "Should not send anything on API failure")
    }
}
