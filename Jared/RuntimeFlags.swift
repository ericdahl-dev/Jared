//
//  RuntimeFlags.swift
//  Jared
//
//  Port abstracting Jared's runtime on/off state away from direct UserDefaults reads.
//

import Foundation

protocol RuntimeFlags {
    /// True when Jared is globally disabled (no inbound routing except `/enable`).
    var isDisabled: Bool { get }
}

struct UserDefaultsRuntimeFlags: RuntimeFlags {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isDisabled: Bool {
        defaults.bool(forKey: JaredConstants.jaredIsDisabled)
    }
}
