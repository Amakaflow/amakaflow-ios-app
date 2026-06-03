//
//  ProgramWizardEntryPointUITests.swift
//  AmakaFlowCompanionUITests
//
//  AMA-2096 Phase 1: hide v1 entry points into the disconnected multi-week
//  Program Wizard while keeping the wizard implementation behind a flag.
//

import XCTest

final class ProgramWizardEntryPointUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        var launchEnvironment = [
            "UITEST_CLERK_TEST_SESSION": "user_id=user_ama2096,email=ama2096@example.test,name=AMA2096",
            "UITEST_CLERK_EMAIL": "ama2096@example.test",
            "UITEST_CLERK_PASSWORD": "unused-mock-session",
            "UITEST_CLERK_PUBLISHABLE_KEY": ProcessInfo.processInfo.environment["UITEST_CLERK_PUBLISHABLE_KEY"] ?? "pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA==",
            "UITEST_SKIP_ONBOARDING": "true",
            "UITEST_SKIP_APPLE_WATCH": "true",
            "UITEST_USE_FIXTURES": "true",
            "UITEST_FIXTURE_STATE": "empty",
            "UITEST_MODE": "true"
        ]
        if name.contains("ProgramsList") {
            launchEnvironment["UITEST_START_SCREEN"] = "programs"
        }
        app.launchEnvironment = launchEnvironment
        app.launch()
        dismissBlockingModalsIfPresent()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testHomeEmptyStateHidesBuildPlanButKeepsOtherOptions() throws {
        XCTAssertTrue(
            TestAuthHelper.waitForMainContent(app, timeout: 20),
            "App should reach authenticated tab chrome with mock Clerk session"
        )

        let emptyState = app.descendants(matching: .any)["af_home_empty_state"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10), "Home should render the empty state with empty fixtures")

        XCTAssertFalse(
            element("af_home_empty_build_plan").exists,
            "Program Wizard entry should be absent while FeatureFlags.programWizardEnabled is false"
        )

        let justToday = element("af_home_empty_just_today")
        XCTAssertTrue(justToday.exists, "Single-workout option should remain visible")
        XCTAssertTrue(justToday.isHittable, "Single-workout option should remain tappable")

        let coachPicks = element("af_home_empty_coach_picks")
        XCTAssertTrue(coachPicks.exists, "Coach option should remain visible")
        XCTAssertTrue(coachPicks.isHittable, "Coach option should remain tappable")
    }

    func testProgramsListHidesWizardAddButton() throws {
        XCTAssertTrue(
            TestAuthHelper.waitForMainContent(app, timeout: 20),
            "App should reach authenticated tab chrome with mock Clerk session"
        )

        let programsScreen = element("programs_screen")
        XCTAssertTrue(programsScreen.waitForExistence(timeout: 5), "Programs list should open")
        XCTAssertFalse(
            element("programs_add_program").exists,
            "Program Wizard '+' entry should be absent while FeatureFlags.programWizardEnabled is false"
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
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
