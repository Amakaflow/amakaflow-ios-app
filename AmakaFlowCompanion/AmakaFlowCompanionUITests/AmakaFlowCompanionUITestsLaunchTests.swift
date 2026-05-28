//
//  AmakaFlowCompanionUITestsLaunchTests.swift
//  AmakaFlowCompanionUITests
//
//  Created by DAVID ANDREWS on 11/21/25.
//

import XCTest

final class AmakaFlowCompanionUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let processEnvironment = ProcessInfo.processInfo.environment
        let publishableKey = processEnvironment["UITEST_CLERK_PUBLISHABLE_KEY"]
            ?? processEnvironment["CLERK_PUBLISHABLE_KEY_STAGING"]
            ?? processEnvironment["CLERK_PUBLISHABLE_KEY"]

        guard let publishableKey, !publishableKey.isEmpty else {
            throw XCTSkip(
                "Launch screenshot test requires a Clerk publishable key. " +
                "Set UITEST_CLERK_PUBLISHABLE_KEY or CLERK_PUBLISHABLE_KEY_STAGING before running UI tests."
            )
        }

        let app = XCUIApplication()
        app.launchEnvironment["UITEST_CLERK_PUBLISHABLE_KEY"] = publishableKey
        app.launchEnvironment["TEST_ENVIRONMENT"] = processEnvironment["TEST_ENVIRONMENT"] ?? "staging"
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
