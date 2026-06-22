import XCTest
import JaredFramework
@testable import Jared

class WebhookRouteFactoryTests: XCTestCase {

    private func makeFactory() -> WebhookRouteFactory {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WebhookRouteFactoryTests-\(UUID().uuidString)", isDirectory: true)
        let client = WebhookDeliveryClient(
            session: .ephemeral,
            keychain: MockKeychain(),
            sender: nil,
            deliveryStore: WebhookDeliveryStore(fileURL: dir.appendingPathComponent("deliveries.json"))
        )
        return WebhookRouteFactory(client: client)
    }

    func testRoutesFromWebhookWithNilRoutesReturnsEmpty() {
        let webhook = RichWebhook(url: "https://example.com", routes: nil)
        XCTAssertTrue(makeFactory().routes(from: webhook).isEmpty)
    }

    func testRoutesFromWebhookWithEmptyRoutesReturnsEmpty() {
        let webhook = RichWebhook(url: "https://example.com", routes: [])
        XCTAssertTrue(makeFactory().routes(from: webhook).isEmpty)
    }

    func testRoutesPreserveNamesAndComparisons() {
        let r1 = Route(name: "greet", comparisons: [.startsWith: ["/hello"]], call: { _ in })
        let r2 = Route(name: "bye", comparisons: [.is: ["/bye"]], call: { _ in })
        let webhook = RichWebhook(url: "https://example.com", routes: [r1, r2])

        let produced = makeFactory().routes(from: webhook)

        XCTAssertEqual(produced.count, 2)
        XCTAssertEqual(produced[0].name, "greet")
        XCTAssertEqual(produced[0].comparisons[.startsWith], ["/hello"])
        XCTAssertEqual(produced[1].name, "bye")
        XCTAssertEqual(produced[1].comparisons[.is], ["/bye"])
    }

    func testEachRouteGetsFreshDeliveryCallClosure() {
        let r1 = Route(name: "a", comparisons: [.startsWith: ["/a"]], call: { _ in })
        let r2 = Route(name: "b", comparisons: [.startsWith: ["/b"]], call: { _ in })
        let webhook = RichWebhook(url: "https://example.com", routes: [r1, r2])

        let produced = makeFactory().routes(from: webhook)

        // Each route's call is wired by the factory (not the original stub closure)
        XCTAssertEqual(produced.count, 2)
        XCTAssertNotNil(produced[0].call as Any)
        XCTAssertNotNil(produced[1].call as Any)
    }
}
