//
//  MessageMatcher.swift
//  Jared
//

import Foundation
import JaredFramework

/// Decides whether a Route matches a Message, and returns the message
/// to pass to the route's call handler (may differ from the original
/// for .containsURL where the body is replaced with the matched URL).
struct MessageMatcher {

    private let detector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// Returns the message to deliver to `route.call`, or `nil` if the
    /// route does not match. `.containsURL` returns a message whose body
    /// contains only the matched URL string.
    func matchingMessage(route: Route, message: Message) -> Message? {
        guard let textBody = message.body as? TextBody else { return nil }
        let text = textBody.message
        let lower = text.lowercased()

        for (compareType, values) in route.comparisons {
            switch compareType {
            case .startsWith:
                for v in values where lower.hasPrefix(v.lowercased()) {
                    return message
                }

            case .contains:
                for v in values {
                    if v.isEmpty || lower.contains(v.lowercased()) {
                        return message
                    }
                }

            case .is:
                for v in values where lower == v.lowercased() {
                    return message
                }

            case .containsURL:
                let nsText = text as NSString
                let range = NSRange(location: 0, length: nsText.length)
                let urlMatches = detector.matches(in: text, options: [], range: range)
                for match in urlMatches {
                    let url = nsText.substring(with: match.range)
                    for v in values where url.contains(v) {
                        let urlMessage = Message(
                            body: TextBody(url),
                            date: message.date ?? Date(),
                            sender: message.sender,
                            recipient: message.recipient,
                            attachments: []
                        )
                        return urlMessage
                    }
                }

            case .isReaction:
                if message.action != nil { return message }
            }
        }
        return nil
    }
}
