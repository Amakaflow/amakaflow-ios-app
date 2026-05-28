//
//  AmakaFlowCompanionUITestsLaunchTests.swift
//  AmakaFlowCompanionUITests
//
//  Created by DAVID ANDREWS on 11/21/25.
//

import XCTest

enum ClerkLaunchPreflight {
    static var hasPublishableKey: Bool {
        let env = ProcessInfo.processInfo.environment
        return [
            "UITEST_CLERK_PUBLISHABLE_KEY",
            "CLERK_PUBLISHABLE_KEY",
            "CLERK_PUBLISHABLE_KEY_DEV",
            "CLERK_PUBLISHABLE_KEY_STAGING",
            "CLERK_PUBLISHABLE_KEY_PRODUCTION"
        ].contains { key in
            guard let value = env[key] else { return false }
            return !value.isEmpty && !value.hasPrefix("$(")
        }
    }

    static var isCI: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" || env["XCODE_CLOUD"] == "true"
    }

    static func requirePublishableKeyOrSkipLocally() throws {
        guard hasPublishableKey || isCI else {
            throw XCTSkip(
                "Skipping launch screenshot locally because no Clerk publishable key is configured. " +
                "Set UITEST_CLERK_PUBLISHABLE_KEY or CLERK_PUBLISHABLE_KEY_STAGING to run it. CI does not skip this guard."
            )
        }
    }

    static func propagateKeys(to app: XCUIApplication) {
        var launchEnvironment = app.launchEnvironment
        for key in [
            "UITEST_CLERK_PUBLISHABLE_KEY",
            "CLERK_PUBLISHABLE_KEY",
            "CLERK_PUBLISHABLE_KEY_DEV",
            "CLERK_PUBLISHABLE_KEY_STAGING",
            "CLERK_PUBLISHABLE_KEY_PRODUCTION"
        ] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                launchEnvironment[key] = value
            }
        }
        app.launchEnvironment = launchEnvironment
    }
}

final class AmakaFlowCompanionUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        try ClerkLaunchPreflight.requirePublishableKeyOrSkipLocally()

        let app = XCUIApplication()
        ClerkLaunchPreflight.propagateKeys(to: app)
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
