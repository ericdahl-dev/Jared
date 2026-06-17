import XCTest
import JaredFramework

class RouteTests: XCTestCase {

    // MARK: - Compare raw values

    func testCompareRawValues() {
        XCTAssertEqual(Compare.startsWith.rawValue, "startsWith")
        XCTAssertEqual(Compare.contains.rawValue, "contains")
        XCTAssertEqual(Compare.is.rawValue, "is")
        XCTAssertEqual(Compare.containsURL.rawValue, "containsURL")
        XCTAssertEqual(Compare.isReaction.rawValue, "isReaction")
    }

    // MARK: - Route init

    func testRouteInitMinimalPreservesProperties() {
        var called = false
        let route = Route(name: "ping", comparisons: [.startsWith: ["/ping"]], call: { _ in called = true })
        XCTAssertEqual(route.name, "ping")
        XCTAssertEqual(route.comparisons[.startsWith], ["/ping"])
        XCTAssertNil(route.description)
        XCTAssertNil(route.parameterSyntax)
    }

    func testRouteInitWithDescriptionPreservesIt() {
        let route = Route(name: "r", comparisons: [.contains: ["foo"]], call: { _ in }, description: "does foo")
        XCTAssertEqual(route.description, "does foo")
        XCTAssertNil(route.parameterSyntax)
    }

    func testRouteInitWithSyntaxPreservesIt() {
        let route = Route(name: "r", comparisons: [:], call: { _ in }, description: "d", parameterSyntax: "/r,arg")
        XCTAssertEqual(route.parameterSyntax, "/r,arg")
    }

    // MARK: - JSON decoding

    func testRouteDecodesFromJSON() throws {
        let json = """
        {
            "name": "ping",
            "description": "Replies pong",
            "parameterSyntax": "/ping",
            "comparisons": { "startsWith": ["/ping"] }
        }
        """.data(using: .utf8)!

        let route = try JSONDecoder().decode(Route.self, from: json)

        XCTAssertEqual(route.name, "ping")
        XCTAssertEqual(route.description, "Replies pong")
        XCTAssertEqual(route.parameterSyntax, "/ping")
        XCTAssertEqual(route.comparisons[.startsWith], ["/ping"])
    }

    func testRouteDecodesMultipleComparisons() throws {
        let json = """
        {
            "name": "multi",
            "description": "d",
            "parameterSyntax": "/m",
            "comparisons": { "startsWith": ["/m"], "contains": ["foo", "bar"] }
        }
        """.data(using: .utf8)!

        let route = try JSONDecoder().decode(Route.self, from: json)

        XCTAssertEqual(route.comparisons[.startsWith], ["/m"])
        XCTAssertEqual(route.comparisons[.contains], ["foo", "bar"])
    }

    func testCompareDecoderThrowsOnUnknownKey() {
        let json = """
        {
            "name": "test",
            "description": "test",
            "parameterSyntax": "/test",
            "comparisons": { "unknownCompareType": ["/test"] }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(Route.self, from: json),
                             "unknown Compare key must throw DecodingError")
    }
}
