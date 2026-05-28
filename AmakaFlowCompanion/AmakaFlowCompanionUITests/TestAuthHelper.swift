//
//  TestAuthHelper.swift
//  AmakaFlowCompanionUITests
//
//  Helper for configuring app launch with test authentication (AMA-232)
//

import XCTest

/// Configures XCUIApplication for E2E testing with Clerk test authentication
enum TestAuthHelper {
    static let tabBarIdentifier = "af_tabbar"

    static var hasRequiredClerkCredentials: Bool {
        let environment = ProcessInfo.processInfo.environment
        return [
            "UITEST_CLERK_EMAIL",
            "UITEST_CLERK_PASSWORD",
            "UITEST_CLERK_PUBLISHABLE_KEY"
        ].allSatisfy { key in
            guard let value = environment[key] else { return false }
            return !value.isEmpty && !value.hasPrefix("$(")
        }
    }

    static var isCI: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["CI"] == "true"
            || environment["GITHUB_ACTIONS"] == "true"
            || environment["XCODE_CLOUD"] == "true"
    }

    static func requireClerkCredentialsOrSkipLocally() throws {
        guard hasRequiredClerkCredentials || isCI else {
            throw XCTSkip(
                "Skipping authenticated UI E2E locally because Clerk test credentials are not configured. " +
                "Set UITEST_CLERK_EMAIL, UITEST_CLERK_PASSWORD, and UITEST_CLERK_PUBLISHABLE_KEY to run it. CI does not skip this guard."
            )
        }
    }

    /// Configure app with test credentials to sign in with a real Clerk test user
    /// - Parameters:
    ///   - app: The XCUIApplication instance to configure
    ///   - environment: The environment to use (default: development for localhost)
    static func configureApp(_ app: XCUIApplication, environment: String = "development") {
        app.launchArguments = ["--uitesting"]

        // Real Clerk test-user pattern. Tests should drive the Clerk UI with these credentials
        // instead of bypassing backend auth headers. Values are supplied by CI/local env.
        let processEnvironment = ProcessInfo.processInfo.environment
        let clerkEmail = processEnvironment["UITEST_CLERK_EMAIL"] ?? ""
        let clerkPassword = processEnvironment["UITEST_CLERK_PASSWORD"] ?? ""
        let clerkKey = processEnvironment["UITEST_CLERK_PUBLISHABLE_KEY"] ?? ""

        guard !clerkEmail.isEmpty, !clerkPassword.isEmpty, !clerkKey.isEmpty else {
            XCTFail(
                "Missing required Clerk test credentials. Set UITEST_CLERK_EMAIL, " +
                "UITEST_CLERK_PASSWORD, and UITEST_CLERK_PUBLISHABLE_KEY in the environment " +
                "or CI secrets before running UI tests."
            )
            return
        }

        var launchEnv: [String: String] = [
            "UITEST_CLERK_EMAIL": clerkEmail,
            "UITEST_CLERK_PASSWORD": clerkPassword,
            "UITEST_CLERK_PUBLISHABLE_KEY": clerkKey,
            "TEST_ENVIRONMENT": environment
        ]
        // Only set TEST_API_BASE_URL when explicitly provided or running against localhost
        if let apiBaseURL = processEnvironment["TEST_API_BASE_URL"] {
            launchEnv["TEST_API_BASE_URL"] = apiBaseURL
        } else if environment == "development" {
            launchEnv["TEST_API_BASE_URL"] = "http://localhost:8001"
        }
        app.launchEnvironment = launchEnv
    }

    /// Wait for the app to finish loading and show main content
    /// - Parameters:
    ///   - app: The XCUIApplication instance
    ///   - timeout: Maximum time to wait for main content
    /// - Returns: True if main content appeared within timeout
    @discardableResult
    static func waitForMainContent(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        // Look for elements that indicate we're past the pairing screen.
        // AMA-1992 replaced native TabView chrome with a custom six-tab bar,
        // so the primary indicator is the custom tabbar marker or Home tab.
        if tabBar(app).waitForExistence(timeout: timeout) || tab(app, "home_tab", label: "Home").exists {
            return true
        }

        // Fallback: look for Home tab content elements
        let homeContent = app.staticTexts["Today's Workouts"]
        if homeContent.waitForExistence(timeout: 2) {
            return true
        }

        return false
    }

    /// Custom AMA-1992 tab bar container.
    static func tabBar(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements[tabBarIdentifier]
    }

    /// Custom AMA-1992 tab button lookup. Prefer stable accessibility ids,
    /// with a label fallback for older builds still using native TabView.
    static func tab(_ app: XCUIApplication, _ identifier: String, label: String) -> XCUIElement {
        let byIdentifier = app.buttons[identifier]
        if byIdentifier.exists { return byIdentifier }
        return app.buttons[label]
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
