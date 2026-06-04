//
//  InMemoryMessageSource.swift
//  Jared
//

import JaredFramework

/// Test adapter for MessageSource. Push messages directly for unit tests.
class InMemoryMessageSource: MessageSource {
    var onMessage: ((Message) -> Void)?

    func push(_ message: Message) {
        onMessage?(message)
    }
}
