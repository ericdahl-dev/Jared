//
//  InboundFilterPolicy.swift
//  Jared
//

import Foundation
import JaredFramework

/// Decides whether an inbound message should proceed to route matching.
/// Concentrates the self-message, body-type, and global-disabled policy that
/// previously lived inline in `Router.route`.
struct InboundFilterPolicy {
    let flags: RuntimeFlags

    func shouldRoute(_ message: Message) -> Bool {
        if let sender = message.sender as? Person, sender.isMe { return false }
        guard message.body is TextBody || message.action != nil else { return false }

        // `/enable` must work even when Jared is globally disabled, otherwise the
        // user could never turn it back on from iMessage.
        let isEnable = (message.body as? TextBody)?.message.lowercased() == "/enable"
        guard !flags.isDisabled || isEnable else { return false }
        return true
    }
}
