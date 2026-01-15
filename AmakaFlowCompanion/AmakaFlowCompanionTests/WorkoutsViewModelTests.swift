//
//  WorkoutsViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for WorkoutsViewModel
//
//  Updated AMA-350: Now uses AppDependencies.mock for proper dependency injection
//  instead of demo mode flag.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutsViewModelTests: XCTestCase {

    var viewModel: WorkoutsViewModel!
    var mockAPIService: MockAPIService!
    var mockPairingService: MockPairingService!

    override func setUp() async throws {
        // Create mock dependencies
        mockAPIService = MockAPIService()
        mockPairingService = MockPairingService()

        // Configure mock pairing service as "paired" so API calls are attempted
        mockPairingService.configurePaired()

        // Configure mock API to return test workouts
        let testWorkouts = [
            TestFixtures.workout(id: "w1", name: "Strength Training", sport: .strength),
            TestFixtures.workout(id: "w2", name: "Running Intervals", sport: .running),
            TestFixtures.workout(id: "w3", name: "Speed Drills", sport: .running)
        ]
        let scheduledWorkouts = testWorkouts.prefix(2).map { workout in
            ScheduledWorkout(workout: workout, scheduledDate: Date(), scheduledTime: nil, syncedToApple: false)
        }

        mockAPIService.fetchWorkoutsResult = .success(Array(testWorkouts))
        mockAPIService.fetchScheduledWorkoutsResult = .success(Array(scheduledWorkouts))
        mockAPIService.fetchPushedWorkoutsResult = .success([])
        mockAPIService.fetchPendingWorkoutsResult = .success([])

        // Create dependencies container with mocks
        let dependencies = AppDependencies(
            apiService: mockAPIService,
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )

        // Create ViewModel with mock dependencies
        viewModel = WorkoutsViewModel(dependencies: dependencies)
        await viewModel.loadWorkouts()
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPIService = nil
        mockPairingService = nil
    }

    // MARK: - Initial State Tests

    func testInitialStateHasMockData() {
        // ViewModel loads workouts from mock API
        XCTAssertFalse(viewModel.upcomingWorkouts.isEmpty, "Should have upcoming workouts")
        XCTAssertFalse(viewModel.incomingWorkouts.isEmpty, "Should have incoming workouts")
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)

        // Verify API was called
        XCTAssertTrue(mockAPIService.fetchWorkoutsCalled, "Should have fetched workouts")
        XCTAssertTrue(mockAPIService.fetchScheduledWorkoutsCalled, "Should have fetched scheduled workouts")
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
        viewModel.searchQuery = "running"

        let filtered = viewModel.filteredIncoming
        XCTAssertTrue(filtered.allSatisfy { workout in
            workout.name.localizedCaseInsensitiveContains("running") ||
            workout.sport.rawValue.localizedCaseInsensitiveContains("running")
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

    // MARK: - Mark Workout Completed Tests (AMA-237)

    func testMarkWorkoutCompletedRemovesFromIncoming() {
        // Given workouts in incoming list
        guard let workoutToComplete = viewModel.incomingWorkouts.first else {
            XCTFail("No workouts in incoming list")
            return
        }
        let workoutId = workoutToComplete.id
        let initialCount = viewModel.incomingWorkouts.count

        // When marking as completed
        viewModel.markWorkoutCompleted(workoutId)

        // Then workout is removed from incoming
        XCTAssertEqual(viewModel.incomingWorkouts.count, initialCount - 1)
        XCTAssertFalse(viewModel.incomingWorkouts.contains(where: { $0.id == workoutId }))
    }

    func testMarkWorkoutCompletedRemovesFromUpcoming() {
        // Given workouts in upcoming list
        guard let scheduledToComplete = viewModel.upcomingWorkouts.first else {
            XCTFail("No workouts in upcoming list")
            return
        }
        let workoutId = scheduledToComplete.workout.id
        let initialCount = viewModel.upcomingWorkouts.count

        // When marking as completed
        viewModel.markWorkoutCompleted(workoutId)

        // Then workout is removed from upcoming
        XCTAssertEqual(viewModel.upcomingWorkouts.count, initialCount - 1)
        XCTAssertFalse(viewModel.upcomingWorkouts.contains(where: { $0.workout.id == workoutId }))
    }

    func testMarkWorkoutCompletedWithNonExistentId() {
        // Given
        let initialIncomingCount = viewModel.incomingWorkouts.count
        let initialUpcomingCount = viewModel.upcomingWorkouts.count

        // When marking non-existent workout as completed
        viewModel.markWorkoutCompleted("non-existent-id-12345")

        // Then counts remain unchanged
        XCTAssertEqual(viewModel.incomingWorkouts.count, initialIncomingCount)
        XCTAssertEqual(viewModel.upcomingWorkouts.count, initialUpcomingCount)
    }

    func testMarkWorkoutCompletedRemovesFromBothLists() {
        // Create a workout that exists in both incoming and upcoming (same ID)
        let sharedWorkout = Workout(
            id: "shared-workout-id",
            name: "Shared Workout",
            sport: .strength,
            duration: 1800,
            intervals: [],
            source: .ai
        )

        // Add to incoming
        viewModel.incomingWorkouts.append(sharedWorkout)

        // Add to upcoming
        let scheduled = ScheduledWorkout(
            workout: sharedWorkout,
            scheduledDate: Date(),
            scheduledTime: nil,
            syncedToApple: false
        )
        viewModel.upcomingWorkouts.append(scheduled)

        // When marking as completed
        viewModel.markWorkoutCompleted("shared-workout-id")

        // Then workout is removed from both lists
        XCTAssertFalse(viewModel.incomingWorkouts.contains(where: { $0.id == "shared-workout-id" }))
        XCTAssertFalse(viewModel.upcomingWorkouts.contains(where: { $0.workout.id == "shared-workout-id" }))
    }

    // MARK: - Notification Observer Tests (AMA-237)

    func testWorkoutCompletedNotificationTriggersRemoval() async {
        // Given a workout in the list
        guard let workout = viewModel.incomingWorkouts.first else {
            XCTFail("No workouts in incoming list")
            return
        }
        let workoutId = workout.id

        // When posting notification
        NotificationCenter.default.post(
            name: .workoutCompleted,
            object: nil,
            userInfo: ["workoutId": workoutId]
        )

        // Wait for notification to be processed on main queue
        await Task.yield()

        // Then workout should be removed
        XCTAssertFalse(viewModel.incomingWorkouts.contains(where: { $0.id == workoutId }))
    }

    func testWorkoutCompletedNotificationWithMissingUserInfo() async {
        // Given
        let initialCount = viewModel.incomingWorkouts.count

        // When posting notification without userInfo
        NotificationCenter.default.post(
            name: .workoutCompleted,
            object: nil,
            userInfo: nil
        )

        // Wait for notification to be processed
        await Task.yield()

        // Then counts remain unchanged (no crash)
        XCTAssertEqual(viewModel.incomingWorkouts.count, initialCount)
    }
}
