//
//  TestDoubles.swift
//  AmakaFlowCompanionTests
//
//  Centralized test doubles and factory methods for creating test fixtures.
//  Provides convenient access to mock implementations and test data builders.
//
//  Part of AMA-349: Test Infrastructure
//

import Foundation
@testable import AmakaFlowCompanion

// MARK: - Test Fixture Factory

/// Factory for creating test fixtures with sensible defaults
/// Follows builder pattern for easy customization
enum TestFixtures {

    // MARK: - Workout Fixtures

    /// Create a basic test workout with customizable intervals
    static func workout(
        id: String = "test-workout-\(UUID().uuidString.prefix(8))",
        name: String = "Test Workout",
        sport: WorkoutSport = .strength,
        duration: Int = 600,
        intervals: [WorkoutInterval]? = nil,
        description: String? = "A test workout",
        source: Workout.WorkoutSource = .coach
    ) -> Workout {
        Workout(
            id: id,
            name: name,
            sport: sport,
            duration: duration,
            intervals: intervals ?? defaultIntervals,
            description: description,
            source: source
        )
    }

    /// Default intervals for test workouts
    static var defaultIntervals: [WorkoutInterval] {
        [
            .warmup(seconds: 30, target: "Easy pace"),
            .reps(sets: nil, reps: 10, name: "Push-ups", load: nil, restSec: 15, followAlongUrl: nil),
            .time(seconds: 60, target: "Plank hold"),
            .cooldown(seconds: 30, target: nil)
        ]
    }

    /// Create a simple timed workout (warmup, work, cooldown)
    static func timedWorkout(
        warmupSeconds: Int = 30,
        workSeconds: Int = 60,
        cooldownSeconds: Int = 30
    ) -> Workout {
        workout(
            name: "Timed Workout",
            intervals: [
                .warmup(seconds: warmupSeconds, target: nil),
                .time(seconds: workSeconds, target: "Work"),
                .cooldown(seconds: cooldownSeconds, target: nil)
            ]
        )
    }

    /// Create a reps-based workout (good for testing set/rep logic)
    static func repsWorkout(
        sets: Int = 3,
        reps: Int = 10,
        restSeconds: Int? = 60
    ) -> Workout {
        workout(
            name: "Reps Workout",
            intervals: [
                .reps(sets: sets, reps: reps, name: "Exercise", load: nil, restSec: restSeconds, followAlongUrl: nil)
            ]
        )
    }

    /// Create a repeat/circuit workout
    static func circuitWorkout(
        rounds: Int = 3,
        exerciseSeconds: Int = 30,
        restSeconds: Int = 15
    ) -> Workout {
        workout(
            name: "Circuit Workout",
            intervals: [
                .repeat(reps: rounds, intervals: [
                    .time(seconds: exerciseSeconds, target: "Work"),
                    .time(seconds: restSeconds, target: "Rest")
                ])
            ]
        )
    }

    // MARK: - User Profile Fixtures

    /// Create a test user profile
    static func userProfile(
        userId: String = "test-user-\(UUID().uuidString.prefix(8))",
        email: String = "test@example.com",
        name: String = "Test User"
    ) -> UserProfile {
        UserProfile(userId: userId, email: email, name: name)
    }

    // MARK: - Saved Progress Fixtures

    /// Create saved workout progress for resume testing
    static func savedProgress(
        workoutId: String = "test-workout-1",
        workoutName: String = "Test Workout",
        currentStepIndex: Int = 2,
        elapsedSeconds: Int = 120,
        savedAt: Date = Date()
    ) -> SavedWorkoutProgress {
        SavedWorkoutProgress(
            workoutId: workoutId,
            workoutName: workoutName,
            currentStepIndex: currentStepIndex,
            elapsedSeconds: elapsedSeconds,
            savedAt: savedAt
        )
    }
}

// MARK: - Mock Dependencies Container

/// Container for mock dependencies used in testing
/// Provides easy access to all mocks with pre-configured defaults
@MainActor
final class TestDependencies {
    let apiService: MockAPIService
    let pairingService: MockPairingService
    let audioService: MockAudioService
    let progressStore: MockProgressStore
    let watchSession: MockWatchSession
    let clock: TestClock

    init(
        apiService: MockAPIService = MockAPIService(),
        pairingService: MockPairingService = MockPairingService(),
        audioService: MockAudioService = MockAudioService(),
        progressStore: MockProgressStore = MockProgressStore(),
        watchSession: MockWatchSession = MockWatchSession(),
        clock: TestClock = TestClock()
    ) {
        self.apiService = apiService
        self.pairingService = pairingService
        self.audioService = audioService
        self.progressStore = progressStore
        self.watchSession = watchSession
        self.clock = clock
    }

    /// Create a WorkoutEngine with these test dependencies
    func makeWorkoutEngine() -> WorkoutEngine {
        WorkoutEngine(
            clock: clock,
            audioService: audioService,
            progressStore: progressStore,
            pairingService: pairingService
        )
    }

    /// Reset all mocks to their initial state
    func reset() {
        // Reset API service tracking
        apiService.fetchWorkoutsCalled = false
        apiService.fetchScheduledWorkoutsCalled = false
        apiService.fetchPushedWorkoutsCalled = false
        apiService.fetchPendingWorkoutsCalled = false
        apiService.syncWorkoutCalled = false
        apiService.syncedWorkout = nil
        apiService.getAppleExportCalled = false
        apiService.parseVoiceWorkoutCalled = false
        apiService.transcribeAudioCalled = false
        apiService.syncPersonalDictionaryCalled = false
        apiService.fetchPersonalDictionaryCalled = false
        apiService.logManualWorkoutCalled = false
        apiService.postWorkoutCompletionCalled = false
        apiService.postedCompletion = nil
        apiService.confirmSyncCalled = false
        apiService.confirmedWorkoutId = nil
        apiService.reportSyncFailedCalled = false
        apiService.fetchProfileCalled = false

        // Reset pairing service tracking
        pairingService.markAuthInvalidCalled = false
        pairingService.authRestoredCalled = false
        pairingService.pairCalled = false
        pairingService.pairCode = nil
        pairingService.refreshTokenCalled = false
        pairingService.getTokenCalled = false
        pairingService.unpairCalled = false

        // Reset audio service tracking
        audioService.speakCalled = false
        audioService.lastSpokenText = nil
        audioService.lastSpeechPriority = nil
        audioService.stopSpeakingCalled = false
        audioService.announceWorkoutStartCalled = false
        audioService.announceStepCalled = false
        audioService.announceCountdownCalled = false
        audioService.announceWorkoutCompleteCalled = false
        audioService.announcePausedCalled = false
        audioService.announceResumedCalled = false
        audioService.announceRestCalled = false

        // Reset progress store tracking
        progressStore.saveCalled = false
        progressStore.loadCalled = false
        progressStore.clearCalled = false
        progressStore.storedProgress = nil

        // Reset watch session
        watchSession.reset()

        // Reset clock
        clock.reset()
    }
}

// MARK: - Test Helpers

extension MockPairingService {
    /// Configure the mock as a paired user
    func configurePaired(
        token: String = "test-token",
        userId: String = "test-user-id",
        email: String = "test@example.com",
        name: String = "Test User"
    ) {
        isPaired = true
        storedToken = token
        userProfile = UserProfile(userId: userId, email: email, name: name)
        needsReauth = false
    }

    /// Configure the mock as unpaired
    func configureUnpaired() {
        isPaired = false
        storedToken = nil
        userProfile = nil
        needsReauth = false
    }
}

extension MockAPIService {
    /// Configure successful workout fetch response
    func configureWorkouts(_ workouts: [Workout]) {
        fetchWorkoutsResult = .success(workouts)
        fetchScheduledWorkoutsResult = .success([])
        fetchPushedWorkoutsResult = .success(workouts)
        fetchPendingWorkoutsResult = .success([])
    }

    /// Configure API error responses
    func configureError(_ error: Error) {
        fetchWorkoutsResult = .failure(error)
        fetchScheduledWorkoutsResult = .failure(error)
        fetchPushedWorkoutsResult = .failure(error)
        fetchPendingWorkoutsResult = .failure(error)
        syncWorkoutResult = .failure(error)
    }
}

extension MockProgressStore {
    /// Configure with saved progress for resume testing
    func configureSavedProgress(
        workoutId: String = "test-workout-1",
        workoutName: String = "Test Workout",
        stepIndex: Int = 2,
        elapsedSeconds: Int = 120
    ) {
        storedProgress = TestFixtures.savedProgress(
            workoutId: workoutId,
            workoutName: workoutName,
            currentStepIndex: stepIndex,
            elapsedSeconds: elapsedSeconds
        )
    }
}

// MARK: - XCTest Extensions

import XCTest

extension XCTestCase {
    /// Create test dependencies for use in a test method
    @MainActor
    func makeTestDependencies() -> TestDependencies {
        TestDependencies()
    }

    /// Wait for async operations to settle
    func waitForAsync(seconds: TimeInterval = 0.1) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
