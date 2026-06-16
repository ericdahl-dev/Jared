//
//  WebhookDeliveryTests.swift
//  JaredTests
//

import XCTest
import CryptoKit
import JaredFramework
@testable import Jared

class WebhookDeliveryTests: XCTestCase {
    let WEBHOOK_URL = "https://github.com/zekesnider/jaredwebhook"
    let SAMPLE_MESSAGE = Message(
        body: TextBody("hello there jared"),
        date: Date(timeIntervalSince1970: 1495061841),
        sender: Person(givenName: "zeke", handle: "zeke@email.com", isMe: true),
        recipient: Person(givenName: "jared", handle: "jared@email.com", isMe: false)
    )

    var config: URLSessionConfiguration!
    var sender: JaredMock!
    var keychain: MockKeychain!

    override func setUp() {
        config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        sender = JaredMock()
        keychain = MockKeychain()
        URLProtocolMock.reset()
    }

    override func tearDown() {
        URLProtocolMock.reset()
    }

    // MARK: - Headers

    func testDeliveryIdHeaderPresent() {
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        let webhook = RichWebhook(url: WEBHOOK_URL)
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        let deliveryId = URLProtocolMock.capturedRequests.first?.value(forHTTPHeaderField: "X-Jared-Delivery-Id")
        XCTAssertNotNil(deliveryId, "X-Jared-Delivery-Id header should be present")
        XCTAssertNotNil(UUID(uuidString: deliveryId ?? ""), "X-Jared-Delivery-Id should be a valid UUID")
    }

    func testWebhookIdHeaderMatchesURL() {
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        let webhook = RichWebhook(url: WEBHOOK_URL)
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        let webhookId = URLProtocolMock.capturedRequests.first?.value(forHTTPHeaderField: "X-Jared-Webhook-Id")
        XCTAssertEqual(webhookId, WEBHOOK_URL, "X-Jared-Webhook-Id should equal webhook URL")
    }

    // MARK: - HMAC signing

    func testHMACSignatureAddedWhenSecretPresent() {
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        let webhook = RichWebhook(url: WEBHOOK_URL, auth: WebhookAuth(secret: "test-secret"))
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        guard let req = URLProtocolMock.capturedRequests.first else {
            XCTFail("No request was made"); return
        }
        let sigHeader = req.value(forHTTPHeaderField: "X-Jared-Signature")
        XCTAssertNotNil(sigHeader, "X-Jared-Signature should be present when auth is configured")
        XCTAssertTrue(sigHeader?.hasPrefix("sha256=") ?? false, "Signature should start with sha256=")

        // Verify the HMAC matches the actual request body
        // URLSession may convert httpBody to httpBodyStream internally
        let body: Data
        if let direct = req.httpBody {
            body = direct
        } else if let stream = req.httpBodyStream {
            body = Data(reading: stream)
        } else {
            XCTFail("No request body in captured request"); return
        }
        let key = SymmetricKey(data: Data("test-secret".utf8))
        let sig = HMAC<SHA256>.authenticationCode(for: body, using: key)
        let expected = "sha256=" + sig.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(sigHeader, expected, "HMAC-SHA256 signature should match computed value")
    }

    func testNoSignatureWhenSecretMissing() {
        // auth field set but no secret in keychain → deliver unsigned, no crash
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        let webhook = RichWebhook(url: WEBHOOK_URL, auth: WebhookAuth(secret: nil))
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        XCTAssertEqual(URLProtocolMock.capturedRequests.count, 1, "Should still deliver when secret is missing")
        let sigHeader = URLProtocolMock.capturedRequests.first?.value(forHTTPHeaderField: "X-Jared-Signature")
        XCTAssertNil(sigHeader, "No signature header should be added when secret is missing")
    }

    // MARK: - Retry logic

    func testFourxxDoesNotRetry() {
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        URLProtocolMock.responseStatusCode = 400
        let webhook = RichWebhook(url: WEBHOOK_URL)
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.retryDelayBase = 10_000_000
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        XCTAssertEqual(URLProtocolMock.capturedRequests.count, 1, "4xx should not retry — exactly 1 attempt")
    }

    func testFivexxRetriesThenSucceeds() {
        // First 2 attempts return 500, third returns 200
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        URLProtocolMock.responseSequence = [500, 500, 200]
        let webhook = RichWebhook(url: WEBHOOK_URL)
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.retryDelayBase = 10_000_000
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        XCTAssertEqual(URLProtocolMock.capturedRequests.count, 3, "Should retry on 5xx until success — 3 attempts total")
    }

    func testRetryExhausted() {
        // All attempts return 500 — should make exactly maxRetries+1 = 4 attempts then give up
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        URLProtocolMock.responseStatusCode = 500
        let webhook = RichWebhook(url: WEBHOOK_URL)
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.retryDelayBase = 10_000_000
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        XCTAssertEqual(URLProtocolMock.capturedRequests.count, 4, "Should exhaust all retries — 1 + 3 = 4 attempts")
    }

    // MARK: - Command mode

    func testCommandModeNoRetryOn5xx() {
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        URLProtocolMock.responseStatusCode = 500
        let webhook = RichWebhook(url: WEBHOOK_URL, mode: .command)
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.retryDelayBase = 10_000_000
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        XCTAssertEqual(URLProtocolMock.capturedRequests.count, 1, "Command mode must never retry — exactly 1 attempt")
    }

    func testCommandModeReplySentOnSuccess() {
        let responseJSON = #"{"success":true,"body":{"message":"pong"}}"#
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data(responseJSON.utf8)]
        URLProtocolMock.responseStatusCode = 200
        let webhook = RichWebhook(url: WEBHOOK_URL, mode: .command)
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        XCTAssertEqual(sender.calls.count, 1, "Command mode should send reply when response is success")
        let repliedText = (sender.calls.first?.body as? TextBody)?.message
        XCTAssertEqual(repliedText, "pong", "Reply text should match webhook response body")
    }

    func testCommandModeNoReplyOnErrorResponse() {
        let responseJSON = #"{"success":false,"error":"something went wrong"}"#
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data(responseJSON.utf8)]
        URLProtocolMock.responseStatusCode = 200
        let webhook = RichWebhook(url: WEBHOOK_URL, mode: .command)
        let wm = WebHookManager(webhooks: [webhook], session: config, sender: sender, keychain: keychain)
        wm.didProcess(message: SAMPLE_MESSAGE)
        sleep(2)

        XCTAssertEqual(sender.calls.count, 0, "Command mode should not send reply when success=false")
    }

    // MARK: - Persistent delivery history

    private func tempDeliveryFileURL() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WebhookDeliveryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("deliveries.json")
    }

    private func sampleRecord(url: String = "https://example.com/hook",
                              deliveryId: String = UUID().uuidString,
                              statusCode: Int? = 200,
                              error: String? = nil,
                              attempt: Int = 1,
                              date: Date = Date()) -> WebhookDeliveryRecord {
        WebhookDeliveryRecord(deliveryId: deliveryId, webhookURL: url, date: date,
                              statusCode: statusCode, errorDescription: error, attempt: attempt)
    }

    func testDeliveryStoreLoadReturnsEmptyWhenFileMissing() {
        let store = WebhookDeliveryStore(fileURL: tempDeliveryFileURL())
        XCTAssertEqual(store.load().count, 0)
    }

    func testDeliveryStoreLoadReturnsEmptyWhenFileCorrupt() throws {
        let url = tempDeliveryFileURL()
        try Data("not json".utf8).write(to: url)
        let store = WebhookDeliveryStore(fileURL: url)
        XCTAssertEqual(store.load().count, 0, "Corrupt file must produce empty log, not crash")
    }

    func testDeliveryStoreAppendAndLoadRoundTrip() {
        let url = tempDeliveryFileURL()
        let store = WebhookDeliveryStore(fileURL: url)
        let rec = sampleRecord(url: "https://example.com/a", statusCode: 200)

        store.append(rec)

        let reloaded = WebhookDeliveryStore(fileURL: url).load()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.deliveryId, rec.deliveryId)
        XCTAssertEqual(reloaded.first?.webhookURL, rec.webhookURL)
        XCTAssertEqual(reloaded.first?.statusCode, 200)
    }

    func testDeliveryStoreNewestFirst() {
        let url = tempDeliveryFileURL()
        let store = WebhookDeliveryStore(fileURL: url)
        let older = sampleRecord(deliveryId: "old", date: Date(timeIntervalSince1970: 1_000))
        let newer = sampleRecord(deliveryId: "new", date: Date(timeIntervalSince1970: 2_000))

        store.append(older)
        store.append(newer)

        let loaded = store.load()
        XCTAssertEqual(loaded.map(\.deliveryId), ["new", "old"], "Records must be stored newest-first")
    }

    func testDeliveryStoreEnforcesCap() {
        let url = tempDeliveryFileURL()
        let store = WebhookDeliveryStore(fileURL: url, maxRecords: 3)
        for i in 0..<5 {
            store.append(sampleRecord(deliveryId: "\(i)",
                                      date: Date(timeIntervalSince1970: Double(i))))
        }
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.deliveryId), ["4", "3", "2"], "Oldest records must be evicted")
    }

    func testDeliveryStorePersistsErrorRecords() {
        let url = tempDeliveryFileURL()
        let store = WebhookDeliveryStore(fileURL: url)
        store.append(sampleRecord(statusCode: nil, error: "timeout"))

        let loaded = store.load()
        XCTAssertEqual(loaded.first?.statusCode, nil)
        XCTAssertEqual(loaded.first?.errorDescription, "timeout")
    }

    // MARK: - WebHookManager integration with persistence

    func testWebHookManagerLoadsExistingDeliveriesOnInit() {
        let fileURL = tempDeliveryFileURL()
        let preloadStore = WebhookDeliveryStore(fileURL: fileURL)
        preloadStore.append(sampleRecord(url: "https://example.com/preloaded",
                                         deliveryId: "preloaded"))

        let webhook = RichWebhook(url: WEBHOOK_URL)
        let wm = WebHookManager(webhooks: [webhook], session: config,
                                sender: sender, keychain: keychain,
                                deliveryStore: WebhookDeliveryStore(fileURL: fileURL))
        XCTAssertEqual(wm.deliveryLog.count, 1)
        XCTAssertEqual(wm.deliveryLog.first?.deliveryId, "preloaded")
    }

    func testWebHookManagerPersistsDelivery() {
        let fileURL = tempDeliveryFileURL()
        let url = URL(string: WEBHOOK_URL)
        URLProtocolMock.testURLs = [url: Data()]
        URLProtocolMock.responseStatusCode = 200

        let webhook = RichWebhook(url: WEBHOOK_URL)
        let wm = WebHookManager(webhooks: [webhook], session: config,
                                sender: sender, keychain: keychain,
                                deliveryStore: WebhookDeliveryStore(fileURL: fileURL))

        let exp = expectation(forNotification: .webhookDelivered, object: wm)
        wm.didProcess(message: SAMPLE_MESSAGE)
        wait(for: [exp], timeout: 5)

        let reloaded = WebhookDeliveryStore(fileURL: fileURL).load()
        XCTAssertEqual(reloaded.count, 1, "Delivery must be persisted to disk")
        XCTAssertEqual(reloaded.first?.webhookURL, WEBHOOK_URL)
        XCTAssertEqual(reloaded.first?.statusCode, 200)
    }
}
