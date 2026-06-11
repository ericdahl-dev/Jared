//
//  URLProtocolMock.swift
//  JaredTests
//
//  Created by Zeke Snider on 2/2/19.
//  Copyright © 2019 Zeke Snider. All rights reserved.
//

import Foundation

extension Data {
    init(reading input: InputStream) {
        self.init()
        input.open()

        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        while input.hasBytesAvailable {
            let read = input.read(buffer, maxLength: bufferSize)
            self.append(buffer, count: read)
        }
        buffer.deallocate()

        input.close()
    }
}

// https://www.hackingwithswift.com/articles/153/how-to-test-ios-networking-code-the-easy-way
class URLProtocolMock: URLProtocol {
    static var testURLs = [URL?: Data]()
    static var matchedDataURLs = [URL]()
    /// HTTP status code returned for all requests. Defaults to 200.
    static var responseStatusCode: Int = 200
    /// Per-call status codes — index 0 = first request, index 1 = second, etc.
    /// Falls back to responseStatusCode once the sequence is exhausted.
    static var responseSequence: [Int] = []
    /// All requests received in order — use .count to verify retry attempts.
    static var capturedRequests: [URLRequest] = []
    private static var callCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        URLProtocolMock.capturedRequests.append(request)
        let idx = URLProtocolMock.callCount
        let statusCode: Int
        if idx < URLProtocolMock.responseSequence.count {
            statusCode = URLProtocolMock.responseSequence[idx]
        } else {
            statusCode = URLProtocolMock.responseStatusCode
        }
        URLProtocolMock.callCount += 1

        if let url = request.url {
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)

            if let data = URLProtocolMock.testURLs[url] {
                URLProtocolMock.matchedDataURLs.append(url)
                client?.urlProtocol(self, didLoad: data)
            }
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }

    static func reset() {
        testURLs = [:]
        matchedDataURLs = []
        responseStatusCode = 200
        responseSequence = []
        capturedRequests = []
        callCount = 0
    }
}
