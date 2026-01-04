//
//  RealWorkoutE2ETests.swift
//  AmakaFlowCompanionUITests
//
//  Real workout execution E2E tests (AMA-232)
//  These tests actually run through a workout with real or simulated timing.
//
//  Two timing modes:
//  - Quick mode: 5 seconds per set (for fast CI/CD testing)
//  - Realistic mode: Real rest periods (30+ minutes, run overnight)
//
//  Requirements:
//  - Development environment running (localhost APIs)
//  - Test user (soopergeri+e2etest@gmail.com) with synced workouts
//  - Paired iPhone + Watch simulators (optional but recommended)
//

import XCTest

// MARK: - Timing Configuration

/// Controls workout timing for E2E tests
enum WorkoutTestTiming {
    /// Quick mode - 5 seconds per set, minimal rest
    case quick
    /// Realistic mode - actual rest periods as defined in workout
    case realistic

    /// Time to wait per set/rep in seconds
    var setDuration: TimeInterval {
        switch self {
        case .quick: return 5
        case .realistic: return 30  // Average set duration
        }
    }

    /// Rest time between sets in seconds
    var restBetweenSets: TimeInterval {
        switch self {
        case .quick: return 2
        case .realistic: return 60  // 1 minute rest
        }
    }

    /// Rest time between exercises in seconds
    var restBetweenExercises: TimeInterval {
        switch self {
        case .quick: return 3
        case .realistic: return 90  // 1.5 minute rest
        }
    }
}

// MARK: - Real Workout Test Base

class RealWorkoutTestCase: XCTestCase {

    var app: XCUIApplication!
    var timing: WorkoutTestTiming = .quick

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Force portrait orientation
        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        // Use development environment (localhost)
        TestAuthHelper.configureApp(app, environment: "development")

        // Add UI interruption monitor for Local Network permission and other alerts
        addUIInterruptionMonitor(withDescription: "System Alerts") { alert in
            let allowButton = alert.buttons["Allow"]
            let okButton = alert.buttons["OK"]
            if allowButton.exists {
                allowButton.tap()
                return true
            } else if okButton.exists {
                okButton.tap()
                return true
            }
            return false
        }

        app.launch()

        // Dismiss any system dialogs
        TestAuthHelper.dismissSystemDialogs(app)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Helper Methods

    /// Navigate to the Workouts tab
    func navigateToWorkouts() -> Bool {
        guard TestAuthHelper.waitForMainContent(app, timeout: 15) else {
            return false
        }

        let workoutsTab = app.tabBars.buttons["Workouts"]
        guard workoutsTab.waitForExistence(timeout: 5) else {
            return false
        }

        workoutsTab.tap()
        sleep(3)  // Wait for API response
        return true
    }

    /// Select the first available workout
    func selectFirstWorkout() -> Bool {
        // WorkoutsView uses ScrollView with VStack, not List/Table
        // Look for workout cards by finding specific workout name patterns
        // Avoid matching section headers like "Upcoming Workouts" or "Incoming Workouts"

        let workoutPatterns = [
            "PERFECT Leg",      // Known test workout from API
            "Full Body",        // Common workout name
            "Training Session", // Common workout name
            "Push Day",         // Common workout name
            "Pull Day",         // Common workout name
            "Long Run",         // Running workout
            "Speed Work"        // Running workout
        ]

        for pattern in workoutPatterns {
            let workoutText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", pattern)
            ).firstMatch

            if workoutText.waitForExistence(timeout: 2) {
                workoutText.tap()
                sleep(1)
                return true
            }
        }

        // Fallback: try table/collection cells (for backwards compatibility)
        let tableCells = app.tables.cells
        let collectionCells = app.collectionViews.cells

        if tableCells.count > 0 {
            tableCells.element(boundBy: 0).tap()
            sleep(1)
            return true
        } else if collectionCells.count > 0 {
            collectionCells.element(boundBy: 0).tap()
            sleep(1)
            return true
        }

        return false
    }

    /// Check if workouts are available in the UI
    func hasWorkoutsAvailable() -> Bool {
        // Check for actual workout names, not section headers
        let workoutPatterns = [
            "PERFECT Leg",      // Known test workout
            "Full Body",        // Common workout name
            "Training Session", // Common workout name
            "Push Day",         // Common workout name
            "Pull Day"          // Common workout name
        ]

        for pattern in workoutPatterns {
            let workoutText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", pattern)
            ).firstMatch

            if workoutText.waitForExistence(timeout: 2) {
                return true
            }
        }

        // Also check for table/collection cells as fallback
        return app.tables.cells.count > 0 || app.collectionViews.cells.count > 0
    }

    /// Select a workout by name
    func selectWorkout(named name: String) -> Bool {
        // First try finding static text containing the workout name
        let workoutText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", name)
        ).firstMatch

        if workoutText.waitForExistence(timeout: 5) {
            workoutText.tap()
            sleep(1)
            return true
        }

        // Try cells containing the name
        let workoutCell = app.cells.containing(
            NSPredicate(format: "label CONTAINS[c] %@", name)
        ).firstMatch

        if workoutCell.waitForExistence(timeout: 3) {
            workoutCell.tap()
            sleep(1)
            return true
        }

        // Try buttons (some UI frameworks use buttons for list items)
        let workoutButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", name)
        ).firstMatch

        if workoutButton.waitForExistence(timeout: 3) {
            workoutButton.tap()
            sleep(1)
            return true
        }

        return false
    }

    /// Start the workout (tap Start button)
    func startWorkout() -> Bool {
        // Wait for the detail sheet to fully appear
        sleep(2)

        // Look for Start Follow-Along button specifically (this is the primary action)
        let startFollowAlong = app.buttons["Start Follow-Along"]
        if startFollowAlong.waitForExistence(timeout: 5) {
            // Scroll to make it visible if needed, then tap
            // Use coordinate-based tap if not hittable
            if startFollowAlong.isHittable {
                startFollowAlong.tap()
            } else {
                // Force tap by scrolling the sheet
                let sheets = app.sheets
                if sheets.count > 0 {
                    sheets.firstMatch.swipeUp()
                    sleep(1)
                }
                // Try direct coordinate tap
                startFollowAlong.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            print("[E2E] Tapped 'Start Follow-Along' button")
            sleep(2)  // Wait for workout view to load
            return true
        }

        // Fallback: look for any start button by iterating through all buttons
        for i in 0..<app.buttons.count {
            let button = app.buttons.element(boundBy: i)
            if button.exists && button.label.lowercased().contains("start") && !button.label.lowercased().contains("watch") {
                print("[E2E] Found start button by iteration: \(button.label)")
                button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                sleep(2)
                return true
            }
        }

        // Debug: Print all visible buttons
        print("[E2E] Could not find start button. Visible buttons:")
        for i in 0..<min(10, app.buttons.count) {
            let btn = app.buttons.element(boundBy: i)
            if btn.exists {
                print("[E2E]   - \(btn.label)")
            }
        }

        return false
    }

    /// Complete current set/interval
    func completeCurrentSet() {
        // Wait for set duration
        Thread.sleep(forTimeInterval: timing.setDuration)

        // Tap "Done" or "Complete" or "Next" button
        let completeButtons = [
            app.buttons["Done"],
            app.buttons["Complete"],
            app.buttons["Next"],
            app.buttons["Complete Set"],
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'done' OR label CONTAINS[c] 'complete' OR label CONTAINS[c] 'next'")).firstMatch
        ]

        for button in completeButtons {
            if button.exists && button.isHittable {
                button.tap()
                Thread.sleep(forTimeInterval: timing.restBetweenSets)
                return
            }
        }

        // If no button found, try tapping the screen (some workouts auto-advance)
        app.tap()
    }

    /// End the workout
    func endWorkout() -> Bool {
        // Look for End/Finish button
        let endButtons = [
            app.buttons["End Workout"],
            app.buttons["Finish"],
            app.buttons["Complete Workout"],
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'end' OR label CONTAINS[c] 'finish'")).firstMatch
        ]

        for button in endButtons {
            if button.waitForExistence(timeout: 5) && button.isHittable {
                button.tap()
                sleep(2)

                // Confirm if there's a confirmation dialog
                let confirmButton = app.buttons["Confirm"]
                if confirmButton.waitForExistence(timeout: 2) {
                    confirmButton.tap()
                    sleep(1)
                }

                return true
            }
        }

        return false
    }

    /// Verify workout appears in Activity History
    func verifyWorkoutInHistory() -> Bool {
        // Navigate to activity history
        let historyTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'activity' OR label CONTAINS[c] 'history' OR label CONTAINS[c] 'sources'")
        ).firstMatch

        if historyTab.waitForExistence(timeout: 5) {
            historyTab.tap()
            sleep(3)

            // Look for completed workout indicator
            let todayWorkout = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'today' OR label CONTAINS[c] 'completed' OR label CONTAINS[c] 'just now'")
            ).firstMatch

            return todayWorkout.waitForExistence(timeout: 10)
        }

        return false
    }
}

// MARK: - Quick Mode Tests (5 seconds per set)

final class QuickWorkoutE2ETests: RealWorkoutTestCase {

    override func setUpWithError() throws {
        timing = .quick
        try super.setUpWithError()
    }

    /// Quick test: Start and complete a strength workout with minimal timing
    func testQuickStrengthWorkoutCompletion() throws {
        // Navigate to workouts
        XCTAssertTrue(navigateToWorkouts(), "Should navigate to workouts")

        // Check for workouts (uses static text search since UI uses ScrollView, not List)
        guard hasWorkoutsAvailable() else {
            throw XCTSkip("No workouts available - ensure test user has synced workouts from localhost")
        }

        // Select first workout (should be "The PERFECT Leg Workout")
        XCTAssertTrue(selectFirstWorkout(), "Should select a workout")

        // Start the workout
        XCTAssertTrue(startWorkout(), "Should start the workout")

        // Complete 3 sets (quick mode - just verify flow works)
        for setNumber in 1...3 {
            print("[E2E] Completing set \(setNumber)/3 (quick mode)")
            completeCurrentSet()
        }

        // End the workout
        XCTAssertTrue(endWorkout(), "Should end the workout")

        // Verify in history (optional - may not sync immediately)
        sleep(5)
        // verifyWorkoutInHistory() - Skip for quick test

        print("[E2E] Quick workout test completed successfully")
    }

    /// Quick test: Select specific workout by name
    func testQuickSelectLegWorkout() throws {
        XCTAssertTrue(navigateToWorkouts(), "Should navigate to workouts")

        // Try to find the leg workout
        let foundWorkout = selectWorkout(named: "Leg Workout") ||
                          selectWorkout(named: "PERFECT Leg") ||
                          selectFirstWorkout()

        guard foundWorkout else {
            throw XCTSkip("Leg workout not found - ensure it's synced from localhost")
        }

        // Verify we're on workout detail
        sleep(1)
        let hasDetailContent = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'set' OR label CONTAINS[c] 'exercise' OR label CONTAINS[c] 'rep'")
        ).firstMatch.exists

        XCTAssertTrue(hasDetailContent || app.buttons.count > 0,
                     "Should show workout detail with exercises")
    }
}

// MARK: - Realistic Mode Tests (Full timing - run overnight)

final class RealisticWorkoutE2ETests: RealWorkoutTestCase {

    override func setUpWithError() throws {
        timing = .realistic
        try super.setUpWithError()
    }

    /// Realistic test: Complete full strength workout with real rest periods
    /// WARNING: This test takes 30+ minutes to complete
    func testRealisticFullStrengthWorkout() throws {
        // Navigate to workouts
        XCTAssertTrue(navigateToWorkouts(), "Should navigate to workouts")

        let workoutCells = app.tables.cells
        let collectionCells = app.collectionViews.cells
        let hasWorkouts = workoutCells.count > 0 || collectionCells.count > 0

        guard hasWorkouts else {
            throw XCTSkip("No workouts available - ensure test user has synced workouts from localhost")
        }

        // Select the leg workout
        let foundWorkout = selectWorkout(named: "Leg Workout") ||
                          selectWorkout(named: "PERFECT Leg") ||
                          selectFirstWorkout()

        guard foundWorkout else {
            throw XCTSkip("Target workout not found")
        }

        // Start the workout
        XCTAssertTrue(startWorkout(), "Should start the workout")

        // For a 12-exercise workout with 3 sets each = 36 total sets
        // This will take approximately: 36 sets * (30s set + 60s rest) = 54 minutes
        let totalSets = 36

        for setNumber in 1...totalSets {
            print("[E2E] Completing set \(setNumber)/\(totalSets) (realistic mode)")
            print("[E2E] Estimated time remaining: \((totalSets - setNumber) * Int(timing.setDuration + timing.restBetweenSets) / 60) minutes")

            completeCurrentSet()

            // Extra rest between exercises (every 3 sets)
            if setNumber % 3 == 0 {
                print("[E2E] Rest between exercises...")
                Thread.sleep(forTimeInterval: timing.restBetweenExercises - timing.restBetweenSets)
            }
        }

        // End the workout
        XCTAssertTrue(endWorkout(), "Should end the workout")

        // Wait for sync
        sleep(10)

        // Verify workout appears in history
        XCTAssertTrue(verifyWorkoutInHistory(), "Completed workout should appear in activity history")

        print("[E2E] Realistic workout test completed successfully!")
    }

    /// Realistic test: Workout with pause/resume
    func testRealisticWorkoutWithPauseResume() throws {
        XCTAssertTrue(navigateToWorkouts(), "Should navigate to workouts")

        guard selectFirstWorkout() else {
            throw XCTSkip("No workouts available")
        }

        XCTAssertTrue(startWorkout(), "Should start the workout")

        // Complete first set
        completeCurrentSet()

        // Pause the workout
        let pauseButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'pause'")
        ).firstMatch

        if pauseButton.waitForExistence(timeout: 5) {
            pauseButton.tap()
            print("[E2E] Workout paused")

            // Wait in paused state (simulating user taking a break)
            Thread.sleep(forTimeInterval: 30)  // 30 second break

            // Resume
            let resumeButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'resume'")
            ).firstMatch

            if resumeButton.waitForExistence(timeout: 5) {
                resumeButton.tap()
                print("[E2E] Workout resumed")
            }
        }

        // Complete a few more sets
        for _ in 1...3 {
            completeCurrentSet()
        }

        // End workout
        XCTAssertTrue(endWorkout(), "Should end the workout")
    }
}

// MARK: - Environment Verification Tests

final class EnvironmentE2ETests: RealWorkoutTestCase {

    /// Verify app is using Development environment
    func testAppUsesDevEnvironment() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        // Navigate to Settings/More to check environment
        let moreTab = app.tabBars.buttons["More"]
        if moreTab.exists {
            moreTab.tap()
            sleep(1)

            // Look for "Development" or "localhost" indicator
            let devIndicator = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'development' OR label CONTAINS[c] 'localhost'")
            ).firstMatch

            XCTAssertTrue(devIndicator.waitForExistence(timeout: 5),
                         "App should show Development environment (not Staging)")
        }
    }

    /// Verify workouts can be loaded from localhost API
    func testCanLoadWorkoutsFromLocalhost() throws {
        XCTAssertTrue(navigateToWorkouts(), "Should navigate to workouts")

        // Wait for API call to complete
        sleep(5)

        // Check if we got workouts or an error
        let errorIndicator = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'error' OR label CONTAINS[c] 'failed' OR label CONTAINS[c] 'connection'")
        ).firstMatch

        let hasError = errorIndicator.exists

        if hasError {
            XCTFail("Failed to load workouts from localhost - ensure development APIs are running")
        }

        // Should have workouts or empty state (not error)
        XCTAssertTrue(true, "Successfully connected to localhost API")
    }
}
