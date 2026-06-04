//
//  MessageSource.swift
//  Jared
//

import JaredFramework

/// A source of incoming messages. Implementors call `onMessage` for each new message.
protocol MessageSource: AnyObject {
    var onMessage: ((Message) -> Void)? { get set }
}
