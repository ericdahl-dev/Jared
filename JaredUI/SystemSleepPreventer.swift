//
//  SystemSleepPreventer.swift
//  JaredUI
//

import Foundation
import IOKit.pwr_mgt

/// Holds an IOPM assertion that prevents idle system sleep while allowing the display to sleep.
final class SystemSleepPreventer {
    static let shared = SystemSleepPreventer()

    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    deinit {
        releaseAssertion()
    }

    func start() {
        syncWithUserDefaults()
    }

    func stop() {
        releaseAssertion()
    }

    @objc private func defaultsChanged() {
        syncWithUserDefaults()
    }

    private func syncWithUserDefaults() {
        if UserDefaults.standard.bool(forKey: JaredConstants.preventSystemSleep) {
            acquireAssertion()
        } else {
            releaseAssertion()
        }
    }

    private func acquireAssertion() {
        guard !isActive else { return }

        let reason = "Jared is preventing system sleep for iMessage polling" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
        } else {
            NSLog("SystemSleepPreventer: IOPMAssertionCreateWithName failed (%d)", result)
        }
    }

    private func releaseAssertion() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}
