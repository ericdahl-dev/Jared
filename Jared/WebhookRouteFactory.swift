//
//  WebhookRouteFactory.swift
//  Jared
//

import Foundation
import JaredFramework

/// Maps a `RichWebhook` into `[Route]` with live delivery handlers, eliminating the
/// "patch empty closure at runtime" pattern that previously lived in `updateHooks`.
struct WebhookRouteFactory {
    let client: WebhookDeliveryClient

    func routes(from webhook: RichWebhook) -> [Route] {
        (webhook.routes ?? []).map { route in
            var r = route
            let hook = webhook
            r.call = { [client] msg in
                Task { await client.deliver(hook, message: msg) }
            }
            return r
        }
    }
}
