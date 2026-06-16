//
//  MessageTests.swift
//  JaredTests
//
//  Created by Zeke Snider on 2/3/19.
//  Copyright © 2019 Zeke Snider. All rights reserved.
//

import XCTest
import JaredFramework
@testable import Jared

class JaredWebServerTest: XCTestCase {
    static let validBody = "{\"body\": {\"message\": \"[TEST ONLY] JaredWebServerTest\"},\"recipient\": {\"handle\": \"jared-webserver-test@example.invalid\"}}"
    static let invalidBody = "{dskjfal/iqwkjfdslol}"
    
    var jaredMock: JaredMock!
    var testDatabaseLocation: URL!
    var webServer: JaredWebServer!
    
    override func setUp() {
        jaredMock = JaredMock()
        let configuration = WebserverConfiguration(port: 0)
        webServer = JaredWebServer(sender: jaredMock, configuration: configuration)
    }
    
    override func tearDown() {
        webServer?.stop()
        webServer = nil
        jaredMock = nil
    }
    
    func testInvalidRequest() {
        // Start the server
        XCTAssertTrue(webServer.start(), "Server should start successfully for the test")
        let requestURL = URL(string: "http://localhost:\(webServer.listeningPort)/message")!
        
        // Make an invalid post request
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = JaredWebServerTest.invalidBody.data(using: String.Encoding.utf8)
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        var httpResponse: HTTPURLResponse?
        let badRequestPromise = XCTestExpectation(description: "bad request response received")
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            httpResponse = response as? HTTPURLResponse
            badRequestPromise.fulfill()
        }.resume()
        
        wait(for: [badRequestPromise], timeout: 5)
        XCTAssertEqual(httpResponse?.statusCode, 400, "Bad request status header")
        
        // Stop the server
        webServer.stop()
        
        // Make a request and verify that it doesn't work
        var requestError: Error?
        let noResponsePromise = XCTestExpectation(description: "no response received")
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            requestError = error
            noResponsePromise.fulfill()
        }.resume()
        wait(for: [noResponsePromise], timeout: 5)
        print()
        XCTAssertEqual(requestError?.localizedDescription, "Could not connect to the server.", "Request fails when the server is stopped")
    }
    
    func testValidRequest() {
        // Start the server
        XCTAssertTrue(webServer.start(), "Server should start successfully for the test")
        let requestURL = URL(string: "http://localhost:\(webServer.listeningPort)/message")!
        
        // Make an invalid post request
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = JaredWebServerTest.validBody.data(using: String.Encoding.utf8)
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        var httpResponse: HTTPURLResponse?
        let promise = XCTestExpectation(description: "response received")
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            httpResponse = response as? HTTPURLResponse
            promise.fulfill()
        }.resume()
        
        wait(for: [promise], timeout: 5)
        XCTAssertEqual(httpResponse?.statusCode, 200, "Valid request is successful")
        XCTAssertEqual(jaredMock.calls.count, 1, "One message sent")
        XCTAssertEqual((jaredMock.calls[0].body as! TextBody).message, "[TEST ONLY] JaredWebServerTest", "Message was correct")
        XCTAssertEqual((jaredMock.calls[0].recipient as! AbstractRecipient).handle, "jared-webserver-test@example.invalid", "recipient email is correct")
    }

    func testValidRequestReturnsStatusOkBody() {
        XCTAssertTrue(webServer.start())
        let requestURL = URL(string: "http://localhost:\(webServer.listeningPort)/message")!

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = JaredWebServerTest.validBody.data(using: .utf8)
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var responseData: Data?
        let promise = XCTestExpectation(description: "response received")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            responseData = data
            promise.fulfill()
        }.resume()

        wait(for: [promise], timeout: 5)
        let body = responseData.flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(body, "{\"status\": \"ok\"}")
    }

    func testBearerTokenRejectsMissingAuthorization() {
        webServer = JaredWebServer(sender: jaredMock, configuration: WebserverConfiguration(port: 0, bearerToken: "secret"))
        XCTAssertTrue(webServer.start())
        let requestURL = URL(string: "http://localhost:\(webServer.listeningPort)/message")!

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = JaredWebServerTest.validBody.data(using: .utf8)
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var httpResponse: HTTPURLResponse?
        let promise = XCTestExpectation(description: "unauthorized response received")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            httpResponse = response as? HTTPURLResponse
            promise.fulfill()
        }.resume()

        wait(for: [promise], timeout: 5)
        XCTAssertEqual(httpResponse?.statusCode, 401)
        XCTAssertEqual(jaredMock.calls.count, 0)
    }

    func testBearerTokenAcceptsValidAuthorization() {
        webServer = JaredWebServer(sender: jaredMock, configuration: WebserverConfiguration(port: 0, bearerToken: "secret"))
        XCTAssertTrue(webServer.start())
        let requestURL = URL(string: "http://localhost:\(webServer.listeningPort)/message")!

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = JaredWebServerTest.validBody.data(using: .utf8)
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer secret", forHTTPHeaderField: "Authorization")

        var httpResponse: HTTPURLResponse?
        let promise = XCTestExpectation(description: "authorized response received")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            httpResponse = response as? HTTPURLResponse
            promise.fulfill()
        }.resume()

        wait(for: [promise], timeout: 5)
        XCTAssertEqual(httpResponse?.statusCode, 200)
        XCTAssertEqual(jaredMock.calls.count, 1)
    }

    func testStartFailsWhenPortAlreadyInUse() {
        XCTAssertTrue(webServer.start(), "Primary server should start successfully")

        let conflictingServer = JaredWebServer(sender: JaredMock(),
                                               configuration: WebserverConfiguration(port: webServer.listeningPort))

        XCTAssertFalse(conflictingServer.start(), "Second server should fail to bind an in-use port")
    }
}
