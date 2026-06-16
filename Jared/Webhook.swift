//
//  Webhook.swift
//  Jared
//
//  Created by Zeke Snider on 8/16/20.
//  Copyright © 2020 Zeke Snider. All rights reserved.
//

import Foundation
import JaredFramework

// MARK: - Webhook mode

enum WebhookMode: String, Codable {
    case notify  // retries OK; response body ignored
    case command // NO retry (enforced); response body sent as iMessage reply
}

// MARK: - Policy types

struct WebhookAuth: Codable {
    var secret: String?
}

struct DeliveryPolicy: Codable {
    var timeoutSeconds: Double?
}

struct FailurePolicy: Codable {
    var maxRetries: Int?
}

// MARK: - RichWebhook

struct RichWebhook: Decodable {
    var url: String
    var isEnabled: Bool
    var mode: WebhookMode
    var routes: [Route]?
    var auth: WebhookAuth?
    var deliveryPolicy: DeliveryPolicy
    var failurePolicy: FailurePolicy

    // mode=command always enforces 0 retries to prevent duplicate iMessage replies (D17)
    var effectiveMaxRetries: Int {
        mode == .command ? 0 : (failurePolicy.maxRetries ?? 3)
    }

    var effectiveTimeout: Double {
        deliveryPolicy.timeoutSeconds ?? 10.0
    }

    // Backward-compatible decoder: handles both old {url, routes} and new full format
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        mode = (try? c.decodeIfPresent(WebhookMode.self, forKey: .mode)) ?? .notify
        routes = try? c.decodeIfPresent([Route].self, forKey: .routes)
        auth = try? c.decodeIfPresent(WebhookAuth.self, forKey: .auth)
        deliveryPolicy = (try? c.decodeIfPresent(DeliveryPolicy.self, forKey: .deliveryPolicy)) ?? DeliveryPolicy()
        failurePolicy = (try? c.decodeIfPresent(FailurePolicy.self, forKey: .failurePolicy)) ?? FailurePolicy()
    }

    init(url: String, isEnabled: Bool = true, mode: WebhookMode = .notify, routes: [Route]? = nil,
         auth: WebhookAuth? = nil, deliveryPolicy: DeliveryPolicy = DeliveryPolicy(),
         failurePolicy: FailurePolicy = FailurePolicy()) {
        self.url = url
        self.isEnabled = isEnabled
        self.mode = mode
        self.routes = routes
        self.auth = auth
        self.deliveryPolicy = deliveryPolicy
        self.failurePolicy = failurePolicy
    }

    private enum CodingKeys: String, CodingKey {
        case url, isEnabled = "enabled", mode, routes, auth, deliveryPolicy, failurePolicy
    }
}

// MARK: - Response

struct WebhookResponse: Decodable {
    var success: Bool
    var body: TextBody?
    var error: String?
}

// MARK: - URL validation

public enum WebhookURLError: Error, Equatable {
    case empty
    case invalid
    case missingScheme
    case unsupportedScheme(String)
    case missingHost

    public var message: String {
        switch self {
        case .empty: return "Enter a URL"
        case .invalid: return "Not a valid URL"
        case .missingScheme: return "URL must start with http:// or https://"
        case .unsupportedScheme(let scheme): return "Scheme \(scheme):// is not supported"
        case .missingHost: return "URL is missing a host"
        }
    }
}

public enum WebhookURLValidator {
    public static func validate(_ input: String) -> Result<URL, WebhookURLError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let components = URLComponents(string: trimmed) else { return .failure(.invalid) }
        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty else {
            return .failure(.missingScheme)
        }
        guard ["http", "https"].contains(scheme) else {
            return .failure(.unsupportedScheme(scheme))
        }
        guard let host = components.host, !host.isEmpty else { return .failure(.missingHost) }
        guard let url = components.url else { return .failure(.invalid) }
        return .success(url)
    }
}

// MARK: - Delivery record

public struct WebhookDeliveryRecord: Codable {
    public let deliveryId: String
    public let webhookURL: String
    public let date: Date
    public let statusCode: Int?
    public let errorDescription: String?
    public let attempt: Int
}

public extension Notification.Name {
    static let webhookDelivered = Notification.Name("com.jared.webhookDelivered")
}

// MARK: - Delivery store (persistent, on disk)

/// Persists `WebhookDeliveryRecord`s to a JSON file so the management UI can show
/// delivery history across launches. Records are stored newest-first and capped
/// at `maxRecords` (oldest evicted on overflow). All I/O is best-effort —
/// corrupt or missing files are treated as an empty log so the app never
/// crashes on a bad state file.
public final class WebhookDeliveryStore {
    public static let defaultMaxRecords = 200

    private let fileURL: URL
    private let maxRecords: Int
    private let ioQueue = DispatchQueue(label: "com.jared.webhookDeliveryStore")

    public init(fileURL: URL, maxRecords: Int = WebhookDeliveryStore.defaultMaxRecords) {
        self.fileURL = fileURL
        self.maxRecords = maxRecords
    }

    public func load() -> [WebhookDeliveryRecord] {
        ioQueue.sync { readLocked() }
    }

    public func append(_ record: WebhookDeliveryRecord) {
        ioQueue.sync {
            var current = readLocked()
            current.insert(record, at: 0)
            if current.count > maxRecords {
                current = Array(current.prefix(maxRecords))
            }
            writeLocked(current)
        }
    }

    private func readLocked() -> [WebhookDeliveryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WebhookDeliveryRecord].self, from: data)) ?? []
    }

    private func writeLocked(_ records: [WebhookDeliveryRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
