//
//  SendRateLimiter.swift
//  Jared
//
//  Per-handle concurrency limiter for `/send` repeat operations. Pulled out of
//  CoreModule so the limit is deterministic and testable without async timing.
//

import Foundation

final class SendRateLimiter {
    private let max: Int
    private var inFlight: [String: Int] = [:]

    init(max: Int) {
        self.max = max
    }

    /// Reserves a slot for `handle`. Returns false (no reservation) if `handle`
    /// is already at the maximum concurrent sends.
    func tryAcquire(_ handle: String) -> Bool {
        let current = inFlight[handle] ?? 0
        guard current < max else { return false }
        inFlight[handle] = current + 1
        return true
    }

    /// Releases one slot for `handle`.
    func release(_ handle: String) {
        guard let current = inFlight[handle], current > 0 else { return }
        inFlight[handle] = current - 1
    }
}
