//
//  AmakaFlowWatch_Watch_AppUITests.swift
//  AmakaFlowWatch Watch AppUITests
//
//  Smoke tests for AmakaFlow Watch app (AMA-553)
//  Verifies basic app launch, main screen visibility, and absence of errors.
//

import XCTest

final class AmakaFlowWatch_Watch_AppUITests: XCTestCase {

    var app: XCUIApplication!

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

        app = XCUIApplication()
        // Launch arguments for test mode
        app.launchArguments = [
            "--uitesting",
            "--reset-state"
        ]
        app.launchEnvironment = [
            "UITEST_MODE": "1"
        ]

        // Dismiss system dialogs (HealthKit, notifications)
        addUIInterruptionMonitor(withDescription: "HealthKit Authorization") { alert in
            // Accept HealthKit permissions
            let allowButton = alert.buttons["Allow"]
            let dontAllowButton = alert.buttons["Don't Allow"]
            if allowButton.exists {
                allowButton.tap()
                return true
            } else if dontAllowButton.exists {
                dontAllowButton.tap()
                return true
            }
            return false
        }

        addUIInterruptionMonitor(withDescription: "Notification Authorization") { alert in
            let allowButton = alert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Smoke Tests

    @MainActor
    func testAppLaunchesSuccessfully() throws {
        app.launch()

        // Verify the app launched without crashing
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout(15)),
                      "Watch app should launch and reach foreground state")

        // Take a screenshot of the initial launch state
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Watch App Launch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMainScreenLoads() throws {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout(15)))

        // The app entry point is WatchRemoteView which shows different states:
        // - "Connecting..." (loading)
        // - "No Active Workout" (idle, with Refresh and Demo buttons)
        // - "iPhone Not Connected" (disconnected, with Retry and Demo buttons)
        // In test/simulator, we expect either idle or disconnected view.

        // Wait for loading to finish.
        // On CI without a paired iPhone, the app's 5s loading timeout must fire
        // before transitioning. With x86_64 emulation this takes longer.
        let idleText = app.staticTexts["No Active Workout"]
        let disconnectedText = app.staticTexts["iPhone Not Connected"]
        let connectingText = app.staticTexts["Connecting..."]

        // First, wait for the connecting state to resolve
        if connectingText.waitForExistence(timeout: timeout(3)) {
            // Wait for it to transition to idle or disconnected
            let resolved = idleText.waitForExistence(timeout: timeout(15))
                || disconnectedText.waitForExistence(timeout: timeout(5))
            XCTAssertTrue(resolved, "Loading state should resolve to idle or disconnected")
        } else {
            // Already past loading, check for expected states
            let hasExpectedState = idleText.waitForExistence(timeout: timeout(5)) || disconnectedText.exists
            XCTAssertTrue(hasExpectedState,
                          "Main screen should show 'No Active Workout' or 'iPhone Not Connected'")
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Watch Main Screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testDemoButtonExists() throws {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout(15)))

        // Wait for the main screen to load past connecting state
        let idleText = app.staticTexts["No Active Workout"]
        let disconnectedText = app.staticTexts["iPhone Not Connected"]

        let mainScreenLoaded = idleText.waitForExistence(timeout: timeout(15))
            || disconnectedText.waitForExistence(timeout: timeout(5))
        XCTAssertTrue(mainScreenLoaded, "Main screen should load")

        // Both idle and disconnected views have a "Demo" button
        let demoButton = app.buttons["Demo"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: timeout(5)),
                      "Demo button should be present on idle/disconnected screen")
    }

    @MainActor
    func testRefreshButtonExists() throws {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout(15)))

        // Wait for main screen
        let idleText = app.staticTexts["No Active Workout"]
        let disconnectedText = app.staticTexts["iPhone Not Connected"]
        _ = idleText.waitForExistence(timeout: timeout(15))
            || disconnectedText.waitForExistence(timeout: timeout(5))

        // Idle view has "Refresh", disconnected view has "Retry"
        let refreshButton = app.buttons["Refresh"]
        let retryButton = app.buttons["Retry"]
        XCTAssertTrue(refreshButton.exists || retryButton.exists,
                      "Refresh or Retry button should be present")
    }

    @MainActor
    func testNoErrorDialogsOnLaunch() throws {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout(15)))

        // Wait for main screen to settle
        if isCI { sleep(5) } else { sleep(3) }

        // Check for error/crash dialogs
        let errorAlerts = app.alerts
        if errorAlerts.count > 0 {
            let alertScreenshot = XCTAttachment(screenshot: app.screenshot())
            alertScreenshot.name = "Unexpected Alert"
            alertScreenshot.lifetime = .keepAlways
            add(alertScreenshot)

            XCTFail("Unexpected alert dialog appeared: \(errorAlerts.firstMatch.label)")
        }
    }

    @MainActor
    func testDemoModeActivation() throws {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout(15)))

        // Wait for main screen
        let idleText = app.staticTexts["No Active Workout"]
        let disconnectedText = app.staticTexts["iPhone Not Connected"]
        let loaded = idleText.waitForExistence(timeout: timeout(15))
            || disconnectedText.waitForExistence(timeout: timeout(5))
        XCTAssertTrue(loaded, "Main screen should load")

        // Tap Demo button to enter demo mode
        let demoButton = app.buttons["Demo"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: timeout(5)), "Demo button should exist")
        demoButton.tap()

        // In demo mode, screen 0 shows idle (same as before),
        // then tapping the forward button cycles through demo screens
        // Look for the DEMO indicator text at the bottom
        let demoIndicator = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'DEMO'")
        ).firstMatch
        XCTAssertTrue(demoIndicator.waitForExistence(timeout: timeout(8)),
                      "Demo mode indicator should appear")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Demo Mode Active"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
