//
//  KeychainAccessor.swift
//  Jared
//

import Foundation
import Security

// MARK: - Protocol

protocol KeychainAccessor {
    func secret(for url: String) -> String?
    func save(secret: String, for url: String)
    func delete(for url: String)
}

// MARK: - Production implementation

struct KeychainStore: KeychainAccessor {
    private static let service = "com.jared.webhook"

    func secret(for url: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: url,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(secret: String, for url: String) {
        guard let data = secret.data(using: .utf8) else { return }
        delete(for: url)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: url,
            kSecValueData as String: data
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(for url: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: url
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Test double

final class MockKeychain: KeychainAccessor {
    private var store = [String: String]()

    func secret(for url: String) -> String? { store[url] }
    func save(secret: String, for url: String) { store[url] = secret }
    func delete(for url: String) { store.removeValue(forKey: url) }
}
