//
//  CoachComposerUITests.swift
//  AmakaFlowCompanionUITests
//
//  AMA-2065: Verify the Coach composer remains visible above custom chrome.
//

import XCTest

final class CoachComposerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_CLERK_TEST_SESSION": "user_id=user_ama2065,email=ama2065@example.test,name=AMA2065",
            "UITEST_CLERK_EMAIL": "ama2065@example.test",
            "UITEST_CLERK_PASSWORD": "unused-mock-session",
            "UITEST_CLERK_PUBLISHABLE_KEY": ProcessInfo.processInfo.environment["UITEST_CLERK_PUBLISHABLE_KEY"] ?? "pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA",
            "UITEST_SKIP_ONBOARDING": "true",
            "UITEST_SKIP_APPLE_WATCH": "true",
            "UITEST_USE_FIXTURES": "true",
            "UITEST_MODE": "true"
        ]
        app.launch()
        dismissBlockingModalsIfPresent()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testCoachComposerIsVisibleHittableAndAboveTabBar() throws {
        XCTAssertTrue(
            TestAuthHelper.waitForMainContent(app, timeout: 20),
            "App should reach authenticated tab chrome with mock Clerk session"
        )
        dismissBlockingModalsIfPresent()

        // The custom SwiftUI tab bar exposes duplicate accessibility nodes on
        // some simulator runtimes. Tap the stable Coach tab slot directly, then
        // assert on the screen-specific composer below.
        app.coordinate(withNormalizedOffset: CGVector(dx: 2.5 / 6.0, dy: 0.96)).tap()

        let composer = coachInputField()
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "Coach composer text field should exist")
        XCTAssertTrue(composer.isHittable, "Coach composer text field should be visible and tappable")

        let tabTop = customTabBarTopY()
        XCTAssertLessThanOrEqual(
            composer.frame.maxY,
            tabTop,
            "Coach composer should be laid out above the custom tab bar"
        )

        composer.tap()
        composer.typeText("Can I train today?")

        let sendButton = app.buttons["af_coach_send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "Coach send button should exist")
        XCTAssertTrue(sendButton.isHittable, "Coach send button should be hittable after typing")
    }

    private func customTabBarTopY() -> CGFloat {
        let tabBar = app.otherElements.matching(identifier: TestAuthHelper.tabBarIdentifier).firstMatch
        if tabBar.exists { return tabBar.frame.minY }

        let selectedCoachTab = app.buttons.matching(identifier: "coach_tab").firstMatch
        if selectedCoachTab.exists { return selectedCoachTab.frame.minY }

        // Some iOS 26 SwiftUI snapshots hide the custom tab bar's marker.
        // Fall back to the known bottom chrome lane so the regression still
        // fails when the composer is laid out in the tab-bar region.
        return app.frame.maxY - 72
    }

    private func coachInputField() -> XCUIElement {
        let byIdentifier = app.textFields.matching(identifier: "af_coach_input").firstMatch
        if byIdentifier.exists { return byIdentifier }
        return app.textFields.matching(identifier: "Ask your coach...").firstMatch
    }

    private func dismissBlockingModalsIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }

        let dontAllowButton = springboard.buttons["Don’t Allow"]
        if dontAllowButton.waitForExistence(timeout: 1) {
            dontAllowButton.tap()
        }

        let notNowButton = app.buttons["Not now"]
        if notNowButton.waitForExistence(timeout: 3) {
            notNowButton.tap()
        }
    }
}
