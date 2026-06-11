//
//  WebhookTests.swift
//  Jared
//
//  Created by Zeke Snider on 2/2/19.
//  Copyright © 2019 Zeke Snider. All rights reserved.
//

import XCTest
import JaredFramework

class WebhookTests: XCTestCase {
    let WEBHOOK_TEST_URL = "https://github.com/zekesnider/jaredwebhook"
    let WEBHOOK_TEST_URL_TWO = "https://twitter.com/zekesnider/jaredwebhook"
    let MESSAGE_SERIALIZED = "{\"body\":{\"message\":\"hello there jared\"},\"recipient\":{\"handle\":\"jared@email.com\",\"givenName\":\"jared\",\"isMe\":false},\"sender\":{\"handle\":\"zeke@email.com\",\"givenName\":\"zeke\",\"isMe\":true},\"date\":\"2017-05-17T22:57:21.000Z\"}"
    let SAMPLE_MESSAGE = Message(body: TextBody("hello there jared"), date: Date(timeIntervalSince1970: TimeInterval(1495061841)), sender: Person(givenName: "zeke", handle: "zeke@email.com", isMe: true), recipient: Person(givenName: "jared", handle: "jared@email.com", isMe: false))

    var config: URLSessionConfiguration!
    var sender: JaredMock!

    override func setUp() {
        config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        sender = JaredMock()
        URLProtocolMock.responseStatusCode = 200
    }

    override func tearDown() {
        URLProtocolMock.matchedDataURLs = []
        URLProtocolMock.testURLs = [:]
        URLProtocolMock.responseStatusCode = 200
    }

    func testValidURLsCall() {
        let url = URL(string: WEBHOOK_TEST_URL)
        URLProtocolMock.testURLs = [url: Data(MESSAGE_SERIALIZED.utf8)]
        let webhook = RichWebhook(url: WEBHOOK_TEST_URL, routes: [])
        let webhookManager = WebHookManager(webhooks: [webhook], session: config, sender: sender)

        webhookManager.didProcess(message: SAMPLE_MESSAGE)

        // Task {} is async; brief sleep is sufficient for local delivery
        sleep(2)

        XCTAssertEqual(URLProtocolMock.matchedDataURLs.count, 1, "Webhook should be called once")
    }

    func testTwoWebhooksCall() {
        let url = URL(string: WEBHOOK_TEST_URL)
        let urlTwo = URL(string: WEBHOOK_TEST_URL_TWO)
        URLProtocolMock.testURLs = [
            url: Data(MESSAGE_SERIALIZED.utf8),
            urlTwo: Data(MESSAGE_SERIALIZED.utf8)
        ]
        let webhook = RichWebhook(url: WEBHOOK_TEST_URL, routes: [])
        let webhookTwo = RichWebhook(url: WEBHOOK_TEST_URL_TWO, routes: [])
        let webhookManager = WebHookManager(webhooks: [webhook, webhookTwo], session: config, sender: sender)

        webhookManager.didProcess(message: SAMPLE_MESSAGE)

        sleep(2)

        XCTAssertEqual(URLProtocolMock.matchedDataURLs.count, 2, "Both webhooks should be called")
    }

    func testWebhookWithRoutesDoesNotFireInDidProcess() {
        let url = URL(string: WEBHOOK_TEST_URL)
        URLProtocolMock.testURLs = [url: Data(MESSAGE_SERIALIZED.utf8)]
        let route = Route(name: "test", comparisons: [.startsWith: ["!test"]], call: { _ in })
        let webhookWithRoutes = RichWebhook(url: WEBHOOK_TEST_URL, routes: [route])
        let webhookManager = WebHookManager(webhooks: [webhookWithRoutes], session: config, sender: sender)

        webhookManager.didProcess(message: SAMPLE_MESSAGE)

        sleep(2)

        XCTAssertEqual(URLProtocolMock.matchedDataURLs.count, 0,
                       "Webhook with routes should not fire from didProcess — only from Route.call")
    }

    func testGlobalWebhookFiresAlongsideRoutedWebhook() {
        // Regression test for break→continue bug: second webhook (global) must fire
        // even when the first webhook has routes
        let urlGlobal = URL(string: WEBHOOK_TEST_URL_TWO)
        URLProtocolMock.testURLs = [urlGlobal: Data(MESSAGE_SERIALIZED.utf8)]
        let route = Route(name: "test", comparisons: [.startsWith: ["!test"]], call: { _ in })
        let webhookWithRoutes = RichWebhook(url: WEBHOOK_TEST_URL, routes: [route])
        let globalWebhook = RichWebhook(url: WEBHOOK_TEST_URL_TWO, routes: [])
        let webhookManager = WebHookManager(webhooks: [webhookWithRoutes, globalWebhook], session: config, sender: sender)

        webhookManager.didProcess(message: SAMPLE_MESSAGE)

        sleep(2)

        XCTAssertEqual(URLProtocolMock.matchedDataURLs.count, 1,
                       "Global webhook should fire even when first webhook has routes (break→continue regression)")
    }
}
