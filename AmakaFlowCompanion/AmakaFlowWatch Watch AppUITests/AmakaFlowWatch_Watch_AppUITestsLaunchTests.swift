//
//  AmakaFlowWatch_Watch_AppUITestsLaunchTests.swift
//  AmakaFlowWatch Watch AppUITests
//
//  Launch tests with meaningful verifications for AmakaFlow Watch app (AMA-553)
//

import XCTest

final class AmakaFlowWatch_Watch_AppUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    /// Whether we're running on CI (slower x86_64 emulated simulators)
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }

    /// Timeout multiplier: CI simulators run on x86_64 emulation and need longer waits
    private var timeoutMultiplier: Double {
        isCI ? 3.0 : 1.0
    }

    /// Scaled timeout for CI resilience
    private func timeout(_ base: Double) -> Double {
        base * timeoutMultiplier
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--reset-state"
        ]
        app.launchEnvironment = [
            "UITEST_MODE": "1"
        ]
        app.launch()

        // Verify the app is running
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout(15)),
                      "App should reach foreground state")

        // Wait for main screen to load past any connecting state.
        // On CI without a paired iPhone, WCSession never activates and the app's
        // 5s loading timeout must fire before showing idle/disconnected.
        // With x86_64 emulation overhead, this takes significantly longer.
        let idleText = app.staticTexts["No Active Workout"]
        let disconnectedText = app.staticTexts["iPhone Not Connected"]
        let connectingText = app.staticTexts["Connecting..."]

        // Either we see connecting (which will resolve) or we're already on the main screen
        if connectingText.waitForExistence(timeout: timeout(3)) {
            // Wait for connecting to resolve -- generous timeout for CI
            _ = idleText.waitForExistence(timeout: timeout(15))
                || disconnectedText.waitForExistence(timeout: timeout(5))
        }

        // Verify we're showing a meaningful state, not a blank screen
        let hasMainContent = idleText.exists
            || disconnectedText.exists
            || app.buttons["Demo"].exists
            || app.buttons["Refresh"].exists
            || app.buttons["Retry"].exists
        XCTAssertTrue(hasMainContent, "Launch screen should show main content (not blank)")

        // Capture screenshot
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchWithDemoMode() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--reset-state"
        ]
        app.launchEnvironment = [
            "UITEST_MODE": "1"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout(15)))

        // Wait for main screen
        let idleText = app.staticTexts["No Active Workout"]
        let disconnectedText = app.staticTexts["iPhone Not Connected"]
        _ = idleText.waitForExistence(timeout: timeout(15))
            || disconnectedText.waitForExistence(timeout: timeout(5))

        // Enter demo mode if available
        let demoButton = app.buttons["Demo"]
        if demoButton.waitForExistence(timeout: timeout(5)) {
            demoButton.tap()
            if isCI { sleep(3) } else { sleep(1) }

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Launch - Demo Mode"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
