//
//  AMA1839_CJ01_WorkoutLifecycle_CriticalJourneyTests.swift
//  AmakaFlowCompanionUITests
//
//  AMA-1839 / CJ-01 / Layer 3 (XCUITest).
//  Updated under AMA-1842 to use stable, ticket-tagged
//  `accessibilityIdentifier` selectors instead of brittle text matches.
//
//  Selector strategy (post-AMA-1842):
//    All in-app CTAs on the CJ-01 path now have `ama1842.*`
//    accessibilityIdentifiers attached in source. Look-ups are direct
//    (`app.buttons["ama1842.suggest.button"]`) — no fallback ladder.
//    The "Save & End" alert button is selected by its label because
//    SwiftUI alert buttons are surfaced through the system alert and
//    do not accept arbitrary `accessibilityIdentifier` values.
//
//  Clerk signin (BLOCKED — see AMA-1843):
//    `ClerkKitUI.AuthView` is a vendor SwiftUI view. A grep of the
//    `clerk-ios/Sources/ClerkKitUI/` checkout shows ZERO
//    `accessibilityIdentifier` values anywhere in the SDK, so we
//    cannot deterministically tap the email/password/continue fields
//    from XCUITest. AMA-1843 tracks the UITest-only bypass
//    (UITEST_CLERK_TEST_SESSION env var that programmatically creates
//    a Clerk session via the Backend API and persists the JWT to
//    keychain so the app routes past PairingView). Until 1843 lands,
//    the canonical journey test is gated on that env var being
//    present — when absent, the test skips with a clear message
//    rather than timing out at 30 s. This is the honest reporting
//    path per the AMA-1842 brief.
//

import XCTest

final class AMA1839_CJ01_WorkoutLifecycle_CriticalJourneyTests: XCTestCase {

    // MARK: - State

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        try requireClerkTestSessionOrSkip()
        try ClerkLaunchPreflight.requirePublishableKeyOrSkipLocally()
        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        configureLaunch(app)
        ClerkLaunchPreflight.propagateKeys(to: app)

        PermissionInterruptionHandlers.register(on: self)

        app.launch()
    }

    override func tearDownWithError() throws {
        if let app = app {
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.lifetime = .keepAlways
            attachment.name = "CJ01-L3-final-\(name)"
            add(attachment)
        }
        app?.terminate()
        app = nil
    }

    // MARK: - Tests

    /// CANONICAL CJ-01 happy path. Per blueprint Phase 2, when this test
    /// passes green twice in a row L3 of CJ-01 is Done.
    ///
    /// Currently gated on `UITEST_CLERK_TEST_SESSION` (AMA-1843). When
    /// the env var is absent the test skips — it does NOT silently
    /// pass. Skip is the honest signal: "we can't drive Clerk signin
    /// deterministically, here's the ticket that will fix it."
    func test_signInGenerateSaveEnd__freshInstall__completedWorkoutVisibleAfterReopen() throws {
        try requireClerkTestSessionOrSkip()

        // Step 1 — Signed in (handled by 1843 bypass; verify state).
        XCTAssertTrue(waitForTabBar(timeout: 30),
                      "App did not reach signed-in home (tab bar) within 30 s — UITEST_CLERK_TEST_SESSION bypass may not have hydrated the session")

        // Step 2 — Navigate to Coach (lives under More in this app).
        try openCoachFromMore()

        // Step 3 — Generate a workout via Suggest sheet, then Accept.
        try generateAndAcceptWorkout()

        // Step 4 — Start + Save & End from Home.
        try startAndSaveEndWorkout()

        // Step 5 — Verify persistence in Activity History.
        try assertWorkoutInActivityHistory(timeout: 30)

        // Step 6 — Reopen — terminate + relaunch + assert again.
        app.terminate()
        app.launch()
        PermissionInterruptionHandlers.register(on: self)
        app.tap()

        try assertWorkoutInActivityHistory(timeout: 30)
    }

    /// Permission-handling sanity check. Useful as a pre-flight so a CI
    /// failure on the canonical journey can be quickly attributed to
    /// permission flow vs business flow.
    func test_signIn__permissionDialogAppears__interruptionHandledAndHomeVisible() throws {
        try requireClerkTestSessionOrSkip()
        XCTAssertTrue(
            waitForTabBar(timeout: 30),
            "Tab bar did not appear after signin — either the AMA-1843 bypass failed or a permission dialog was not handled by an interruption monitor"
        )
    }

    // MARK: - Step helpers

    private func openCoachFromMore() throws {
        let profileTab = TestAuthHelper.tab(app, "profile_tab", label: "Profile")
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10),
                      "Profile tab not found — Coach lives under Profile hub (AMA-2292)")
        profileTab.tap()

        let coachTab = TestAuthHelper.tab(app, "coach_tab", label: "Coach")
        XCTAssertTrue(coachTab.waitForExistence(timeout: 10),
                      "Coach entry not found — `coach_tab` missing on Profile hub")
        coachTab.tap()

        let coachRoot = app.descendants(matching: .any)["coach_screen"]
        XCTAssertTrue(coachRoot.waitForExistence(timeout: 5),
                      "Coach root did not render after tapping Profile → Coach")

        let todayTab = TestAuthHelper.tab(app, "today_tab", label: "Today")
        XCTAssertTrue(todayTab.waitForExistence(timeout: 5),
                      "Today tab not found — `today_tab` accessibilityIdentifier missing")
        todayTab.tap()
    }

    private func generateAndAcceptWorkout() throws {
        // Suggest button on Home — this triggers a request and presents
        // the Suggest sheet. The sheet auto-generates on open (no
        // separate "Generate" button in this app), so we wait for the
        // preview state to render before tapping Start.
        let suggest = app.buttons["ama1842.suggest.button"]
        XCTAssertTrue(suggest.waitForExistence(timeout: 10),
                      "Suggest Workout button not found — `ama1842.suggest.button` missing")
        suggest.tap()
        app.tap() // wake interruption monitors

        let preview = app.scrollViews["ama1842.suggest.preview"]
        let previewExists = preview.waitForExistence(timeout: 60)
            || app.otherElements["ama1842.suggest.preview"].waitForExistence(timeout: 5)
        XCTAssertTrue(previewExists,
                      "Suggest preview never rendered — generation may have failed (LLM/network) or the `ama1842.suggest.preview` identifier is on the wrong subtree")

        let start = app.buttons["af_suggest_start"]
        for _ in 0..<8 where !start.isHittable {
            if preview.exists {
                preview.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(start.waitForExistence(timeout: 10),
                      "Start button not found — `af_suggest_start` missing")
        XCTAssertTrue(start.isHittable,
                      "Start button exists but is not hittable — scroll container may not expose it")
        start.tap()
        app.tap()
    }

    private func startAndSaveEndWorkout() throws {
        let endButton = app.buttons["ama1842.endWorkout.button"]
        if !endButton.exists {
            let start = app.buttons["ama1842.start.button"]
            if start.waitForExistence(timeout: 5) {
                start.tap()
                app.tap()
            }
        }

        let phoneOnly = app.buttons["Start on Phone Only"]
        if phoneOnly.waitForExistence(timeout: 5) { phoneOnly.tap() }

        XCTAssertTrue(endButton.waitForExistence(timeout: 30),
                      "End-workout button not found in player — `ama1842.endWorkout.button` missing")
        endButton.tap()

        let saveEnd = app.alerts.buttons["Save & End"]
        XCTAssertTrue(saveEnd.waitForExistence(timeout: 10),
                      "Save & End button not found in End-Workout alert")
        saveEnd.tap()
        app.tap()
    }

    private func assertWorkoutInActivityHistory(timeout: TimeInterval) throws {
        let profileTab = TestAuthHelper.tab(app, "profile_tab", label: "Profile")
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10),
                      "Profile tab not visible — cannot open Activity History")
        profileTab.tap()

        let historyTab = TestAuthHelper.tab(app, "history_tab", label: "Activity History")
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10),
                      "History entry not visible on Profile hub")
        historyTab.tap()

        let firstCell = app.buttons["ama1842.activityHistory.cell.0"]
        let appeared = firstCell.waitForExistence(timeout: timeout)

        XCTAssertTrue(appeared,
                      "Activity History did not show the saved workout (`ama1842.activityHistory.cell.0`) within \(Int(timeout)) s — persistence failed or the cell identifier is missing")
    }

    // MARK: - Configuration

    private func configureLaunch(_ app: XCUIApplication) {
        app.launchArguments = ["--uitesting", "--cj01-l3"]
        var env = app.launchEnvironment
        env["TEST_ENVIRONMENT"] = ProcessInfo.processInfo.environment["TEST_ENVIRONMENT"] ?? "staging"
        for key in [
            "UITEST_CLERK_EMAIL",
            "UITEST_CLERK_PASSWORD",
            "UITEST_CLERK_PUBLISHABLE_KEY",
            "UITEST_CLERK_TEST_SESSION"
        ] {
            if let v = ProcessInfo.processInfo.environment[key] { env[key] = v }
        }
        app.launchEnvironment = env
    }

    // MARK: - Skip helpers

    /// AMA-1843 gate: skip the test cleanly when the Clerk signin
    /// bypass env var is not present, instead of running and timing out
    /// at the (vendor-owned) signin screen. Skips show as warnings in
    /// xcresult, not failures, and surface the unblocking ticket
    /// directly in the test log.
    private func requireClerkTestSessionOrSkip() throws {
        guard ProcessInfo.processInfo.environment["UITEST_CLERK_TEST_SESSION"] != nil else {
            throw XCTSkip(
                "CJ-01 L3 cannot run end-to-end until AMA-1843 lands: " +
                "ClerkKitUI ships no accessibilityIdentifier values, so XCUITest cannot " +
                "drive the signin step. Set UITEST_CLERK_TEST_SESSION=<session_jwt> to " +
                "enable the UITest-only signin bypass once AMA-1843 is implemented."
            )
        }
    }

    // MARK: - Selector helpers

    private func waitForTabBar(timeout: TimeInterval) -> Bool {
        return TestAuthHelper.tabBar(app).waitForExistence(timeout: timeout)
            || TestAuthHelper.tab(app, "today_tab", label: "Today").waitForExistence(timeout: 2)
    }
}
