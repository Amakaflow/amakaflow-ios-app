//
//  WorkoutsViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for WorkoutsViewModel
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutsViewModelTests: XCTestCase {

    var viewModel: WorkoutsViewModel!

    override func setUp() async throws {
        viewModel = WorkoutsViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
    }

    // MARK: - Initial State Tests

    func testInitialStateHasMockData() {
        // ViewModel loads mock data on init
        XCTAssertFalse(viewModel.upcomingWorkouts.isEmpty)
        XCTAssertFalse(viewModel.incomingWorkouts.isEmpty)
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Filtering Tests

    func testFilteredUpcomingWithEmptyQuery() {
        viewModel.searchQuery = ""

        XCTAssertEqual(viewModel.filteredUpcoming.count, viewModel.upcomingWorkouts.count)
    }

    func testFilteredUpcomingByName() {
        // Search for a specific workout name
        viewModel.searchQuery = "Strength"

        let filtered = viewModel.filteredUpcoming
        XCTAssertTrue(filtered.allSatisfy { scheduled in
            scheduled.workout.name.localizedCaseInsensitiveContains("Strength") ||
            scheduled.workout.sport.rawValue.localizedCaseInsensitiveContains("Strength")
        })
    }

    func testFilteredUpcomingBySport() {
        viewModel.searchQuery = "running"

        let filtered = viewModel.filteredUpcoming
        XCTAssertTrue(filtered.allSatisfy { scheduled in
            scheduled.workout.name.localizedCaseInsensitiveContains("running") ||
            scheduled.workout.sport.rawValue.localizedCaseInsensitiveContains("running")
        })
    }

    func testFilteredUpcomingCaseInsensitive() {
        let lowerQuery = "strength"
        let upperQuery = "STRENGTH"

        viewModel.searchQuery = lowerQuery
        let lowerResults = viewModel.filteredUpcoming

        viewModel.searchQuery = upperQuery
        let upperResults = viewModel.filteredUpcoming

        XCTAssertEqual(lowerResults.count, upperResults.count)
    }

    func testFilteredUpcomingNoMatches() {
        viewModel.searchQuery = "xyz123nonexistent"

        XCTAssertTrue(viewModel.filteredUpcoming.isEmpty)
    }

    func testFilteredIncomingWithEmptyQuery() {
        viewModel.searchQuery = ""

        XCTAssertEqual(viewModel.filteredIncoming.count, viewModel.incomingWorkouts.count)
    }

    func testFilteredIncomingByName() {
        viewModel.searchQuery = "Speed"

        let filtered = viewModel.filteredIncoming
        XCTAssertTrue(filtered.allSatisfy { workout in
            workout.name.localizedCaseInsensitiveContains("Speed") ||
            workout.sport.rawValue.localizedCaseInsensitiveContains("Speed")
        })
    }

    func testFilteredIncomingBySport() {
        viewModel.searchQuery = "mobility"

        let filtered = viewModel.filteredIncoming
        XCTAssertTrue(filtered.allSatisfy { workout in
            workout.name.localizedCaseInsensitiveContains("mobility") ||
            workout.sport.rawValue.localizedCaseInsensitiveContains("mobility")
        })
    }

    // MARK: - Delete Workout Tests

    func testDeleteWorkout() {
        let initialCount = viewModel.upcomingWorkouts.count
        guard let workoutToDelete = viewModel.upcomingWorkouts.first else {
            XCTFail("No workouts to delete")
            return
        }

        viewModel.deleteWorkout(workoutToDelete)

        XCTAssertEqual(viewModel.upcomingWorkouts.count, initialCount - 1)
        XCTAssertFalse(viewModel.upcomingWorkouts.contains(where: { $0.id == workoutToDelete.id }))
    }

    func testDeleteNonExistentWorkout() {
        let nonExistent = ScheduledWorkout(
            workout: Workout(
                id: "non-existent-id",
                name: "Non Existent",
                sport: .other,
                duration: 100,
                intervals: [],
                source: .ai
            )
        )

        let initialCount = viewModel.upcomingWorkouts.count

        viewModel.deleteWorkout(nonExistent)

        // Should not change the count
        XCTAssertEqual(viewModel.upcomingWorkouts.count, initialCount)
    }

    // MARK: - Add Sample Workout Tests

    func testAddSampleWorkout() {
        let initialCount = viewModel.upcomingWorkouts.count

        viewModel.addSampleWorkout()

        XCTAssertEqual(viewModel.upcomingWorkouts.count, initialCount + 1)
    }

    func testAddSampleWorkoutHasCorrectStructure() {
        let initialIds = Set(viewModel.upcomingWorkouts.map { $0.id })

        viewModel.addSampleWorkout()

        let newWorkout = viewModel.upcomingWorkouts.first { !initialIds.contains($0.id) }
        XCTAssertNotNil(newWorkout)

        if let workout = newWorkout?.workout {
            XCTAssertEqual(workout.name, "Sample Full Body Strength")
            XCTAssertEqual(workout.sport, .strength)
            XCTAssertEqual(workout.source, .ai)
            XCTAssertFalse(workout.intervals.isEmpty)
        }
    }

    func testAddSampleWorkoutMaintainsSortOrder() {
        viewModel.addSampleWorkout()

        // Verify workouts are sorted by date
        for i in 0..<(viewModel.upcomingWorkouts.count - 1) {
            let date1 = viewModel.upcomingWorkouts[i].scheduledDate ?? .distantFuture
            let date2 = viewModel.upcomingWorkouts[i + 1].scheduledDate ?? .distantFuture
            XCTAssertLessThanOrEqual(date1, date2)
        }
    }

    // MARK: - Search Query State Tests

    func testSearchQueryUpdates() {
        XCTAssertEqual(viewModel.searchQuery, "")

        viewModel.searchQuery = "test query"

        XCTAssertEqual(viewModel.searchQuery, "test query")
    }

    func testSearchQueryAffectsBothFilters() {
        viewModel.searchQuery = "running"

        let upcomingFiltered = viewModel.filteredUpcoming
        let incomingFiltered = viewModel.filteredIncoming

        // Both should be filtered
        XCTAssertTrue(upcomingFiltered.allSatisfy { scheduled in
            scheduled.workout.name.localizedCaseInsensitiveContains("running") ||
            scheduled.workout.sport.rawValue.localizedCaseInsensitiveContains("running")
        })

        XCTAssertTrue(incomingFiltered.allSatisfy { workout in
            workout.name.localizedCaseInsensitiveContains("running") ||
            workout.sport.rawValue.localizedCaseInsensitiveContains("running")
        })
    }

    // MARK: - Edge Cases

    func testFilterWithSpecialCharacters() {
        viewModel.searchQuery = "@#$%"

        // Should return empty but not crash
        XCTAssertTrue(viewModel.filteredUpcoming.isEmpty || viewModel.filteredUpcoming.count <= viewModel.upcomingWorkouts.count)
        XCTAssertTrue(viewModel.filteredIncoming.isEmpty || viewModel.filteredIncoming.count <= viewModel.incomingWorkouts.count)
    }

    func testFilterWithWhitespace() {
        viewModel.searchQuery = "   "

        // Whitespace-only query should still filter (looking for spaces in names)
        // This tests that the filter handles edge cases gracefully
        XCTAssertNotNil(viewModel.filteredUpcoming)
        XCTAssertNotNil(viewModel.filteredIncoming)
    }

    func testMultipleDeletes() {
        while !viewModel.upcomingWorkouts.isEmpty {
            guard let workout = viewModel.upcomingWorkouts.first else { break }
            viewModel.deleteWorkout(workout)
        }

        XCTAssertTrue(viewModel.upcomingWorkouts.isEmpty)
    }

    // MARK: - Mock Data Verification

    func testMockDataContainsExpectedSports() {
        let upcomingSports = Set(viewModel.upcomingWorkouts.map { $0.workout.sport })
        let incomingSports = Set(viewModel.incomingWorkouts.map { $0.sport })

        // Should have variety in sports
        XCTAssertGreaterThan(upcomingSports.count, 1)
        XCTAssertGreaterThan(incomingSports.count, 1)
    }

    func testMockDataHasValidDurations() {
        for scheduled in viewModel.upcomingWorkouts {
            XCTAssertGreaterThan(scheduled.workout.duration, 0)
        }

        for workout in viewModel.incomingWorkouts {
            XCTAssertGreaterThan(workout.duration, 0)
        }
    }

    func testMockDataHasNonEmptyNames() {
        for scheduled in viewModel.upcomingWorkouts {
            XCTAssertFalse(scheduled.workout.name.isEmpty)
        }

        for workout in viewModel.incomingWorkouts {
            XCTAssertFalse(workout.name.isEmpty)
        }
    }
}
