//
//  Clock.swift
//  Jared
//
//  Async sleep port so timed operations (e.g. `/send` delays) run instantly in tests.
//

import Foundation

protocol Clock {
    func sleep(seconds: Int) async
}

struct RealClock: Clock {
    func sleep(seconds: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
    }
}
