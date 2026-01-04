//
//  TestAuthHelper.swift
//  AmakaFlowCompanionUITests
//
//  Helper for configuring app launch with test authentication (AMA-232)
//

import XCTest

/// Configures XCUIApplication for E2E testing with auth bypass
enum TestAuthHelper {

    /// Configure app with test credentials to bypass pairing flow
    /// - Parameters:
    ///   - app: The XCUIApplication instance to configure
    ///   - environment: The environment to use (default: development for localhost)
    static func configureApp(_ app: XCUIApplication, environment: String = "development") {
        // Launch arguments to trigger test mode in the app
        app.launchArguments = [
            "--uitesting",
            "--skip-pairing"
        ]

        // Environment variables with test credentials
        // Uses X-Test-Auth header bypass instead of JWT tokens
        app.launchEnvironment = [
            "TEST_AUTH_SECRET": TestCredentials.testAuthSecret,
            "TEST_USER_ID": TestCredentials.userId,
            "TEST_USER_EMAIL": TestCredentials.userEmail,
            "TEST_API_BASE_URL": TestCredentials.apiBaseURL,
            "TEST_ENVIRONMENT": environment  // "development", "staging", or "production"
        ]
    }

    /// Wait for the app to finish loading and show main content
    /// - Parameters:
    ///   - app: The XCUIApplication instance
    ///   - timeout: Maximum time to wait for main content
    /// - Returns: True if main content appeared within timeout
    @discardableResult
    static func waitForMainContent(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        // Look for elements that indicate we're past the pairing screen
        // The app shows a tab bar with Home, Workouts, etc. when paired
        let tabBar = app.tabBars.firstMatch

        // Wait for tab bar to appear - this is the primary indicator
        if tabBar.waitForExistence(timeout: timeout) {
            return true
        }

        // Fallback: look for Home tab content elements
        let homeContent = app.staticTexts["Today's Workouts"]
        if homeContent.waitForExistence(timeout: 2) {
            return true
        }

        return false
    }

    /// Wait for a specific element to appear
    /// - Parameters:
    ///   - element: The XCUIElement to wait for
    ///   - timeout: Maximum time to wait
    /// - Returns: True if element appeared within timeout
    @discardableResult
    static func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Dismiss any system dialogs that may appear (HealthKit, notifications, Local Network, etc.)
    static func dismissSystemDialogs(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Handle Local Network permission ("Connect AmakaFlowCompanion?")
        let localNetworkAlert = springboard.alerts.containing(
            NSPredicate(format: "label CONTAINS 'Connect'")
        ).firstMatch
        if localNetworkAlert.waitForExistence(timeout: 3) {
            // Tap "Allow" or "OK" to permit local network access
            let allowButton = localNetworkAlert.buttons["Allow"]
            let okButton = localNetworkAlert.buttons["OK"]
            if allowButton.exists {
                allowButton.tap()
            } else if okButton.exists {
                okButton.tap()
            }
            sleep(1)
        }

        // Handle HealthKit authorization
        let healthKitAlert = app.alerts.containing(NSPredicate(format: "label CONTAINS 'Health'")).firstMatch
        if healthKitAlert.waitForExistence(timeout: 2) {
            let allowButton = healthKitAlert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
            }
        }

        // Handle notification permission
        let notificationAlert = app.alerts.containing(NSPredicate(format: "label CONTAINS 'Notifications'")).firstMatch
        if notificationAlert.waitForExistence(timeout: 1) {
            let allowButton = notificationAlert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
            }
        }
    }
}
