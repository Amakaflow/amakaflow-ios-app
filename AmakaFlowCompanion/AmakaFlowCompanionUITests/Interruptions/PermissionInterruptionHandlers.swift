//
//  PermissionInterruptionHandlers.swift
//  AmakaFlowCompanionUITests
//
//  AMA-1839 / CJ-01 / L3 — XCUITest interruption monitor helpers.
//
//  Apple's `addUIInterruptionMonitor(withDescription:handler:)` is the
//  first-class way to dismiss permission and system dialogs during a
//  critical-journey test without polluting the journey itself with
//  conditional `if alert.exists` branches.
//
//  The monitors registered here cover the full set of dialogs CJ-01 can
//  surface on a fresh simulator install:
//    * Local Network ("AmakaFlow would like to find and connect to devices…")
//    * Notifications ("AmakaFlow Would Like to Send You Notifications")
//    * HealthKit (read + write authorization sheet — note this is an
//      in-app sheet, NOT a SpringBoard alert, but we cover both forms)
//    * Motion & Fitness ("Allow access to Motion & Fitness")
//    * Bluetooth ("AmakaFlow Would Like to Use Bluetooth")
//    * Tracking transparency ("Allow AmakaFlow to track…")
//    * Generic "Allow"/"OK" fall-through for anything we missed
//
//  Each monitor MUST return `true` if it handled the interruption so
//  XCUITest stops calling subsequent monitors for the same alert.
//
//  Usage in setUp():
//    PermissionInterruptionHandlers.register(on: self)
//    // immediately after registration, give the system a tap so the
//    // interruption monitor actually fires (Apple gotcha — monitors
//    // only fire on the next user-interaction event):
//    app.tap()
//

import XCTest

enum PermissionInterruptionHandlers {

    /// Register all CJ-01 permission monitors on the given test case.
    /// Returned monitor tokens are intentionally discarded — XCTest
    /// auto-removes them at end of test.
    @discardableResult
    static func register(on testCase: XCTestCase) -> [NSObjectProtocol] {
        var tokens: [NSObjectProtocol] = []

        // 1. Local Network permission — first thing CJ-01 hits on a fresh
        //    sim, because the app discovers Watch / pairing peers on launch.
        tokens.append(testCase.addUIInterruptionMonitor(withDescription: "Local Network") { alert in
            let label = alert.label.lowercased()
            guard label.contains("local network")
                || label.contains("find and connect")
                || label.contains("connect to devices") else { return false }
            return tapPositiveButton(on: alert)
        })

        // 2. Notifications.
        tokens.append(testCase.addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            guard alert.label.lowercased().contains("notification") else { return false }
            // For notifications we always ALLOW so the app's onboarding
            // doesn't fork into a "notifications denied" state we'd then
            // have to assert against separately.
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return tapPositiveButton(on: alert)
        })

        // 3. HealthKit — the iOS HealthKit auth sheet is in-process (not
        //    SpringBoard), so this monitor catches the SpringBoard
        //    confirmation cases (e.g. when a privacy prompt shows) and
        //    the journey itself handles the in-app sheet by tapping
        //    "Turn On All" / "Allow" via accessibility identifiers.
        tokens.append(testCase.addUIInterruptionMonitor(withDescription: "HealthKit") { alert in
            let label = alert.label.lowercased()
            guard label.contains("health") || label.contains("access to your health data") else { return false }
            return tapPositiveButton(on: alert)
        })

        // 4. Motion & Fitness — needed for step / cadence inference.
        tokens.append(testCase.addUIInterruptionMonitor(withDescription: "Motion & Fitness") { alert in
            let label = alert.label.lowercased()
            guard label.contains("motion") || label.contains("fitness") else { return false }
            return tapPositiveButton(on: alert)
        })

        // 5. Bluetooth — for HR strap / external sensor pairing on Quick Start.
        tokens.append(testCase.addUIInterruptionMonitor(withDescription: "Bluetooth") { alert in
            guard alert.label.lowercased().contains("bluetooth") else { return false }
            return tapPositiveButton(on: alert)
        })

        // 6. App Tracking Transparency.
        tokens.append(testCase.addUIInterruptionMonitor(withDescription: "Tracking") { alert in
            let label = alert.label.lowercased()
            guard label.contains("track") else { return false }
            // For tracking we DENY — the journey doesn't depend on it and
            // denying is the safer default if the prompt ever appears.
            if alert.buttons["Ask App Not to Track"].exists {
                alert.buttons["Ask App Not to Track"].tap()
                return true
            }
            return tapPositiveButton(on: alert)
        })

        // 7. Generic fall-through — last-line catch for any unexpected
        //    permission alert we haven't enumerated. Returning true here
        //    masks unexpected dialogs from showing as test failures, so
        //    we keep this monitor LAST and only handle alerts that have
        //    a clearly-positive button.
        tokens.append(testCase.addUIInterruptionMonitor(withDescription: "Generic permission") { alert in
            // Only handle if the alert has a recognizable allow-style button;
            // otherwise let the test see and fail on the alert.
            return tapPositiveButton(on: alert, requirePositiveButton: true)
        })

        return tokens
    }

    /// Tap the most-positive button on the alert. Returns true if a
    /// button was tapped.
    ///
    /// `requirePositiveButton`: when true, only return true if a known
    /// positive button label was found (used for the fall-through monitor
    /// so it doesn't accidentally swallow alerts with "Cancel" only).
    @discardableResult
    private static func tapPositiveButton(on alert: XCUIElement, requirePositiveButton: Bool = false) -> Bool {
        let positiveLabels = [
            "Allow",
            "Allow While Using App",
            "Allow Once",
            "OK",
            "Turn On All",
            "Continue",
            "Yes"
        ]
        for label in positiveLabels {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return true
            }
        }
        if requirePositiveButton { return false }
        // Last resort: tap the first button (rarely correct, so only
        // used when caller did NOT request a strict positive match).
        let firstButton = alert.buttons.element(boundBy: 0)
        if firstButton.exists { firstButton.tap(); return true }
        return false
    }
}
