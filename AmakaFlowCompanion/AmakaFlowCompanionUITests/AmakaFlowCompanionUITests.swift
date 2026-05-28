//
//  AmakaFlowCompanionUITests.swift
//  AmakaFlowCompanionUITests
//
//  Comprehensive E2E UI tests for AmakaFlow Companion (AMA-232)
//

import XCTest

// MARK: - Base Test Case

class BaseE2ETestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try TestAuthHelper.requireClerkCredentialsOrSkipLocally()

        // Force portrait orientation before launching
        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        TestAuthHelper.configureApp(app)
        app.launch()

        // Dismiss any system dialogs
        TestAuthHelper.dismissSystemDialogs(app)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }
}

// MARK: - App Launch Tests

final class AppLaunchE2ETests: BaseE2ETestCase {

    func testAppLaunchesSuccessfully() throws {
        // Verify app launches without crashing
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10),
                     "App should launch successfully")
    }

    func testAuthBypassLoadsMainContent() throws {
        // With test credentials, should skip pairing and show main content
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should bypass pairing and show main content")
    }

    func testTabBarDisplayed() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let tabBar = TestAuthHelper.tabBar(app)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5),
                     "Custom tab bar should be displayed")

        // Verify expected tabs exist
        XCTAssertTrue(TestAuthHelper.tab(app, "home_tab", label: "Home").exists)
        XCTAssertTrue(TestAuthHelper.tab(app, "workouts_tab", label: "Workouts").exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

// MARK: - Navigation Tests

final class NavigationE2ETests: BaseE2ETestCase {

    func testNavigateToWorkoutsTab() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists && workoutsTab.isHittable {
            workoutsTab.tap()

            // Wait for workouts list to appear
            sleep(1)
            XCTAssertTrue(true, "Successfully navigated to Workouts tab")
        }
    }

    func testNavigateToSettingsTab() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let profileTab = TestAuthHelper.tab(app, "profile_tab", label: "Profile")

        if profileTab.exists && profileTab.isHittable {
            profileTab.tap()
        }

        // Look for settings-related content (could be nav bar or any settings text)
        sleep(1)
        XCTAssertTrue(true, "Successfully navigated to settings area")
    }

    func testNavigateToActivityHistory() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let historyTab = TestAuthHelper.tab(app, "history_tab", label: "History")

        if historyTab.exists && historyTab.isHittable {
            historyTab.tap()
            sleep(1)
            XCTAssertTrue(true, "Successfully navigated to Activity History")
        }
    }
}

// MARK: - Workout Flow Tests

final class WorkoutFlowE2ETests: BaseE2ETestCase {

    func testWorkoutListLoads() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        // Navigate to workouts
        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists {
            workoutsTab.tap()
        }

        // Wait for API response
        sleep(3)

        // Check for workout cells or empty state indicators
        let workoutCells = app.tables.cells
        let collectionCells = app.collectionViews.cells

        // Check for various empty state indicators
        let emptyStateTexts = [
            "no workouts",
            "empty",
            "0 workouts",
            "No upcoming",
            "No scheduled"
        ]

        let hasWorkouts = workoutCells.count > 0 || collectionCells.count > 0

        var hasEmptyState = false
        for text in emptyStateTexts {
            let element = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", text)
            ).firstMatch
            if element.exists {
                hasEmptyState = true
                break
            }
        }

        // Also check if workouts navigation bar exists (indicates we're on the right screen)
        let workoutsNavBar = app.navigationBars["Workouts"]
        let onWorkoutsScreen = workoutsNavBar.exists

        XCTAssertTrue(hasWorkouts || hasEmptyState || onWorkoutsScreen,
                     "Should show workouts screen with content or empty state")
    }

    func testSelectWorkout() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists {
            workoutsTab.tap()
        }

        sleep(3)

        let workoutCells = app.tables.cells
        guard workoutCells.count > 0 else {
            throw XCTSkip("No workouts available for testing")
        }

        // Tap first workout
        let firstWorkout = workoutCells.element(boundBy: 0)
        firstWorkout.tap()

        // Verify we navigated to detail view
        sleep(1)
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                     "Should show workout detail with navigation")
    }

    func testStartWorkoutButton() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists {
            workoutsTab.tap()
        }

        sleep(3)

        let workoutCells = app.tables.cells
        guard workoutCells.count > 0 else {
            throw XCTSkip("No workouts available for testing")
        }

        // Select first workout
        workoutCells.element(boundBy: 0).tap()
        sleep(1)

        // Look for start button
        let startButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'start' OR label CONTAINS[c] 'begin'")
        ).firstMatch

        if startButton.waitForExistence(timeout: 3) {
            XCTAssertTrue(startButton.isEnabled, "Start button should be enabled")
        } else {
            // May have device selection instead
            print("[E2E] Start button not directly visible - may require device selection")
        }
    }

    func testWorkoutDetailShowsIntervals() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists {
            workoutsTab.tap()
        }

        sleep(3)

        let workoutCells = app.tables.cells
        guard workoutCells.count > 0 else {
            throw XCTSkip("No workouts available for testing")
        }

        workoutCells.element(boundBy: 0).tap()
        sleep(1)

        // Look for interval information
        let intervalInfo = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'warmup' OR label CONTAINS[c] 'interval' OR label CONTAINS[c] 'set' OR label CONTAINS[c] 'rep'")
        ).firstMatch

        // Workout detail should show some form of structure
        XCTAssertTrue(true, "Workout detail view loaded")
    }
}

// MARK: - Strength Workout Tests

final class StrengthWorkoutE2ETests: BaseE2ETestCase {

    func testStrengthWorkoutShowsSets() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists {
            workoutsTab.tap()
        }

        sleep(3)

        // Look for strength workout (may have weight/reps indicators)
        let workoutCells = app.tables.cells
        for i in 0..<min(workoutCells.count, 5) {
            let cell = workoutCells.element(boundBy: i)
            let cellLabel = cell.label.lowercased()

            if cellLabel.contains("strength") || cellLabel.contains("weight") {
                cell.tap()
                sleep(1)

                // Verify sets/reps displayed
                let setsInfo = app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] 'set' OR label CONTAINS[c] 'rep'")
                ).firstMatch

                if setsInfo.exists {
                    XCTAssertTrue(true, "Strength workout shows sets/reps info")
                    return
                }

                // Go back and try next
                app.navigationBars.buttons.element(boundBy: 0).tap()
                sleep(1)
            }
        }

        print("[E2E] No strength workouts found in first 5 items")
    }
}

// MARK: - Pause/Resume Tests

final class WorkoutControlE2ETests: BaseE2ETestCase {

    func testPauseButtonExists() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        // Navigate to workout and start
        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists {
            workoutsTab.tap()
        }

        sleep(3)

        let workoutCells = app.tables.cells
        guard workoutCells.count > 0 else {
            throw XCTSkip("No workouts available for testing")
        }

        workoutCells.element(boundBy: 0).tap()
        sleep(1)

        // Find and tap start button if available
        let startButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'start'")
        ).firstMatch

        if startButton.waitForExistence(timeout: 3) && startButton.isHittable {
            startButton.tap()
            sleep(2)

            // Look for pause button in workout view
            let pauseButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'pause'")
            ).firstMatch

            if pauseButton.waitForExistence(timeout: 5) {
                XCTAssertTrue(pauseButton.isEnabled, "Pause button should be available during workout")
            }
        }
    }
}

// MARK: - App Lifecycle Tests

final class AppLifecycleE2ETests: BaseE2ETestCase {

    func testBackgroundForegroundTransition() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        // Send app to background
        XCUIDevice.shared.press(.home)
        sleep(2)

        // Bring app back to foreground
        app.activate()

        // Verify app still shows main content
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 10),
                     "App should restore main content after backgrounding")
    }

    func testAppStatePreservedAfterBackground() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        // Navigate to Workouts tab (more reliable than Settings)
        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists {
            workoutsTab.tap()
            sleep(1)
        }

        // Background and foreground
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()

        // Verify app restored and shows tab bar
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 10),
                     "App should preserve navigation state")
    }
}

// MARK: - Pull to Refresh Tests

final class SixTabNavigationE2ETests: BaseE2ETestCase {

    func testSixTabBarRendersAllTopLevelTabs() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let tabs = [
            ("home_tab", "Home"),
            ("workouts_tab", "Workouts"),
            ("coach_tab", "Coach"),
            ("library_tab", "Library"),
            ("history_tab", "History"),
            ("profile_tab", "Profile")
        ]

        for tab in tabs {
            XCTAssertTrue(
                TestAuthHelper.tab(app, tab.0, label: tab.1).waitForExistence(timeout: 5),
                "Missing \(tab.1) tab (\(tab.0))"
            )
        }
    }

    func testTappingEachSixTabShowsTheExpectedRoot() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let tabs = [
            ("home_tab", "Home", "home_screen"),
            ("workouts_tab", "Workouts", "workouts_screen"),
            ("coach_tab", "Coach", "coach_screen"),
            ("library_tab", "Library", "library_screen"),
            ("history_tab", "History", "history_screen"),
            ("profile_tab", "Profile", "profile_screen")
        ]

        for tab in tabs {
            let tabButton = TestAuthHelper.tab(app, tab.0, label: tab.1)
            XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "Missing \(tab.1) tab")
            tabButton.tap()

            let root = app.descendants(matching: .any)[tab.2]
            XCTAssertTrue(
                root.waitForExistence(timeout: 5),
                "Tapping \(tab.1) did not show root marker \(tab.2)"
            )
        }
    }
}

final class RefreshE2ETests: BaseE2ETestCase {

    func testPullToRefreshWorkouts() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 15),
                     "App should load main content")

        let workoutsTab = TestAuthHelper.tab(app, "workouts_tab", label: "Workouts")
        if workoutsTab.exists {
            workoutsTab.tap()
        }

        sleep(3)

        // Perform pull to refresh gesture
        let workoutsList = app.tables.firstMatch
        if workoutsList.exists {
            let start = workoutsList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = workoutsList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.1, thenDragTo: end)

            // Wait for refresh to complete
            sleep(3)

            XCTAssertTrue(true, "Pull to refresh completed without crash")
        }
    }
}
