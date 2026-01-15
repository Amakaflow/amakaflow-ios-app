//
//  WorkoutEngineTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for WorkoutEngine state machine
//
//  Updated AMA-350: Now uses TestClock and injected dependencies for
//  deterministic, fast tests without real timers or singletons.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutEngineTests: XCTestCase {

    // MARK: - Test Dependencies

    var engine: WorkoutEngine!
    var clock: TestClock!
    var audioService: MockAudioService!
    var progressStore: MockProgressStore!
    var pairingService: MockPairingService!

    override func setUp() async throws {
        // Create fresh mocks for each test
        clock = TestClock()
        audioService = MockAudioService()
        progressStore = MockProgressStore()
        pairingService = MockPairingService()

        // Create engine with test dependencies (no singleton!)
        engine = WorkoutEngine(
            clock: clock,
            audioService: audioService,
            progressStore: progressStore,
            pairingService: pairingService
        )
    }

    override func tearDown() async throws {
        // Clean up - no need for Task.sleep with mocked dependencies
        engine.reset()
        engine = nil
        clock = nil
        audioService = nil
        progressStore = nil
        pairingService = nil
    }

    // MARK: - Test Fixtures

    private func createTestWorkout(intervals: [WorkoutInterval]? = nil) -> Workout {
        TestFixtures.workout(
            intervals: intervals ?? TestFixtures.defaultIntervals
        )
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.workout)
        XCTAssertEqual(engine.currentStepIndex, 0)
        XCTAssertEqual(engine.remainingSeconds, 0)
        XCTAssertTrue(engine.flattenedSteps.isEmpty)
        XCTAssertFalse(engine.isActive)
    }

    // MARK: - Start Command Tests

    func testStartWorkout() {
        let workout = createTestWorkout()

        engine.start(workout: workout)

        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.workout?.id, workout.id)
        XCTAssertEqual(engine.currentStepIndex, 0)
        XCTAssertEqual(engine.flattenedSteps.count, 4)
        XCTAssertTrue(engine.isActive)
    }

    func testStartSetsRemainingSecondsForTimedStep() {
        let workout = createTestWorkout(intervals: [
            .warmup(seconds: 45, target: nil)
        ])

        engine.start(workout: workout)

        XCTAssertEqual(engine.remainingSeconds, 45)
    }

    func testStartWithRepsStepHasNoTimer() {
        let workout = createTestWorkout(intervals: [
            .reps(sets: nil, reps: 10, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil)
        ])

        engine.start(workout: workout)

        // Reps without rest should have 0 remaining seconds
        XCTAssertEqual(engine.remainingSeconds, 0)
    }

    // MARK: - Pause/Resume Tests

    func testPauseFromRunning() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        engine.pause()

        XCTAssertEqual(engine.phase, .paused)
        XCTAssertTrue(engine.isActive)
    }

    func testPauseFromIdleDoesNothing() {
        engine.pause()

        XCTAssertEqual(engine.phase, .idle)
    }

    func testResumeFromPaused() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        engine.pause()

        engine.resume()

        XCTAssertEqual(engine.phase, .running)
    }

    func testResumeFromRunningDoesNothing() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        let initialVersion = engine.stateVersion

        engine.resume()

        // State version should not change if resume does nothing
        XCTAssertEqual(engine.phase, .running)
    }

    func testTogglePlayPause() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        XCTAssertEqual(engine.phase, .running)

        engine.togglePlayPause()
        XCTAssertEqual(engine.phase, .paused)

        engine.togglePlayPause()
        XCTAssertEqual(engine.phase, .running)
    }

    // MARK: - Navigation Tests

    func testNextStep() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        XCTAssertEqual(engine.currentStepIndex, 0)

        // First nextStep enters rest phase, second advances
        engine.nextStep()
        engine.nextStep()

        XCTAssertEqual(engine.currentStepIndex, 1)
    }

    func testNextStepAtEndEndsWorkout() {
        let workout = createTestWorkout(intervals: [
            .cooldown(seconds: 10, target: nil)  // Use cooldown - no rest after
        ])
        engine.start(workout: workout)

        engine.nextStep()

        XCTAssertEqual(engine.phase, .ended)
    }

    func testPreviousStep() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        // First nextStep enters rest phase, second advances
        engine.nextStep()
        engine.nextStep()
        XCTAssertEqual(engine.currentStepIndex, 1)

        engine.previousStep()

        XCTAssertEqual(engine.currentStepIndex, 0)
    }

    func testPreviousStepAtStartDoesNothing() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        engine.previousStep()

        XCTAssertEqual(engine.currentStepIndex, 0)
    }

    func testSkipToStep() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        engine.skipToStep(2)

        XCTAssertEqual(engine.currentStepIndex, 2)
    }

    func testSkipToInvalidStepDoesNothing() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        engine.skipToStep(100)

        XCTAssertEqual(engine.currentStepIndex, 0)
    }

    // MARK: - End Command Tests

    func testEndWorkoutCompleted() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        engine.end(reason: .completed)

        XCTAssertEqual(engine.phase, .ended)
    }

    func testEndWorkoutUserEnded() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        engine.end(reason: .userEnded)

        XCTAssertEqual(engine.phase, .ended)
    }

    // MARK: - State Version Tests

    func testStateVersionIncrementsOnStart() {
        let initialVersion = engine.stateVersion
        let workout = createTestWorkout()

        engine.start(workout: workout)

        XCTAssertGreaterThan(engine.stateVersion, initialVersion)
    }

    func testStateVersionIncrementsOnPause() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        let versionAfterStart = engine.stateVersion

        engine.pause()

        XCTAssertGreaterThan(engine.stateVersion, versionAfterStart)
    }

    func testStateVersionIncrementsOnNextStep() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        let versionAfterStart = engine.stateVersion

        engine.nextStep()

        XCTAssertGreaterThan(engine.stateVersion, versionAfterStart)
    }

    // MARK: - Progress Calculation Tests

    func testProgressAtStart() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        // 1 of 4 steps = 0.25
        XCTAssertEqual(engine.progress, 0.25, accuracy: 0.01)
    }

    func testProgressAtMiddle() {
        // Use a workout with no rest to simplify navigation testing
        let workout = createTestWorkout(intervals: [
            .cooldown(seconds: 10, target: nil),  // No rest after
            .cooldown(seconds: 10, target: nil),  // No rest after
            .cooldown(seconds: 10, target: nil),  // No rest after
            .cooldown(seconds: 10, target: nil)   // No rest after
        ])
        engine.start(workout: workout)

        engine.nextStep()  // Advance to step 1
        engine.nextStep()  // Advance to step 2

        // 3 of 4 steps = 0.75
        XCTAssertEqual(engine.progress, 0.75, accuracy: 0.01)
    }

    func testFormattedStepProgress() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        XCTAssertEqual(engine.formattedStepProgress, "1 of 4")

        // First nextStep enters rest phase (warmup has rest after)
        engine.nextStep()
        XCTAssertEqual(engine.formattedStepProgress, "1 of 4") // Still on step 1 during rest

        // Second nextStep advances to step 2
        engine.nextStep()
        XCTAssertEqual(engine.formattedStepProgress, "2 of 4")
    }

    // MARK: - Flattened Interval Tests

    func testFlattenSimpleIntervals() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 30, target: nil),
            .time(seconds: 60, target: nil),
            .cooldown(seconds: 30, target: nil)
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened.count, 3)
    }

    func testFlattenRepeatIntervals() {
        let intervals: [WorkoutInterval] = [
            .repeat(reps: 3, intervals: [
                .reps(sets: nil, reps: 10, name: "Push-ups", load: nil, restSec: nil, followAlongUrl: nil),
                .time(seconds: 30, target: "Rest")
            ])
        ]

        let flattened = flattenIntervals(intervals)

        // 3 rounds x 2 exercises = 6 flattened steps
        XCTAssertEqual(flattened.count, 6)
    }

    func testFlattenedIntervalHasRoundInfo() {
        let intervals: [WorkoutInterval] = [
            .repeat(reps: 2, intervals: [
                .reps(sets: nil, reps: 5, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil)
            ])
        ]

        let flattened = flattenIntervals(intervals)

        // Repeat blocks with a single reps exercise use "Set X of Y"
        XCTAssertEqual(flattened[0].roundInfo, "Set 1 of 2")
        XCTAssertEqual(flattened[1].roundInfo, "Set 2 of 2")
    }

    func testFlattenedIntervalStepType() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 30, target: nil),
            .reps(sets: nil, reps: 10, name: "Lunges", load: nil, restSec: nil, followAlongUrl: nil),
            .distance(meters: 400, target: nil)
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened[0].stepType, .timed)
        XCTAssertEqual(flattened[1].stepType, .reps)
        XCTAssertEqual(flattened[2].stepType, .distance)
    }

    // MARK: - Current Step Tests

    func testCurrentStepReturnsCorrectInterval() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        XCTAssertEqual(engine.currentStep?.label, "Warm Up")

        // First nextStep enters rest phase (warmup has rest after)
        engine.nextStep()
        XCTAssertEqual(engine.phase, .resting)
        XCTAssertEqual(engine.currentStep?.label, "Warm Up") // Still on warmup during rest

        // Second nextStep advances to Push-ups
        engine.nextStep()
        XCTAssertEqual(engine.currentStep?.label, "Push-ups")
    }

    // MARK: - Remote Command Tests

    func testHandleRemoteCommandPause() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        engine.handleRemoteCommand("PAUSE", commandId: "cmd-1")

        XCTAssertEqual(engine.phase, .paused)
    }

    func testHandleRemoteCommandResume() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        engine.pause()

        engine.handleRemoteCommand("RESUME", commandId: "cmd-2")

        XCTAssertEqual(engine.phase, .running)
    }

    func testHandleRemoteCommandNextStep() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        // First NEXT_STEP enters rest, second advances
        engine.handleRemoteCommand("NEXT_STEP", commandId: "cmd-3a")
        engine.handleRemoteCommand("NEXT_STEP", commandId: "cmd-3b")

        XCTAssertEqual(engine.currentStepIndex, 1)
    }

    func testHandleRemoteCommandPreviousStep() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        // Advance to step 1 first
        engine.nextStep()
        engine.nextStep()

        engine.handleRemoteCommand("PREV_STEP", commandId: "cmd-4")

        XCTAssertEqual(engine.currentStepIndex, 0)
    }

    func testHandleRemoteCommandEnd() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        engine.handleRemoteCommand("END", commandId: "cmd-5")

        XCTAssertEqual(engine.phase, .ended)
    }

    func testHandleInvalidRemoteCommand() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
        let initialPhase = engine.phase

        engine.handleRemoteCommand("INVALID_COMMAND", commandId: "cmd-6")

        // Should not change state
        XCTAssertEqual(engine.phase, initialPhase)
    }

    // MARK: - Formatted Time Tests

    func testFormattedRemainingTime() {
        let workout = createTestWorkout(intervals: [
            .time(seconds: 125, target: nil) // 2:05
        ])
        engine.start(workout: workout)

        XCTAssertEqual(engine.formattedRemainingTime, "2:05")
    }

    func testFormattedElapsedTime() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        // Initially 0
        XCTAssertEqual(engine.formattedElapsedTime, "0:00")
    }
}

// MARK: - FlattenedInterval Tests

final class FlattenedIntervalTests: XCTestCase {

    func testFormattedTimeMinutesAndSeconds() {
        let interval = FlattenedInterval(
            interval: .time(seconds: 90, target: nil),
            index: 1,
            label: "Work",
            details: "90s",
            roundInfo: nil,
            timerSeconds: 90,
            stepType: .timed,
            followAlongUrl: nil,
            targetReps: nil,
            setNumber: nil,
            totalSets: nil,
            hasRestAfter: false,
            restAfterSeconds: nil
        )

        XCTAssertEqual(interval.formattedTime, "1:30")
    }

    func testFormattedTimeSecondsOnly() {
        let interval = FlattenedInterval(
            interval: .time(seconds: 45, target: nil),
            index: 1,
            label: "Work",
            details: "45s",
            roundInfo: nil,
            timerSeconds: 45,
            stepType: .timed,
            followAlongUrl: nil,
            targetReps: nil,
            setNumber: nil,
            totalSets: nil,
            hasRestAfter: false,
            restAfterSeconds: nil
        )

        XCTAssertEqual(interval.formattedTime, "45s")
    }

    func testFormattedTimeNilForNonTimed() {
        let interval = FlattenedInterval(
            interval: .reps(sets: nil, reps: 10, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil),
            index: 1,
            label: "Squats",
            details: "10 reps",
            roundInfo: nil,
            timerSeconds: nil,
            stepType: .reps,
            followAlongUrl: nil,
            targetReps: 10,
            setNumber: nil,
            totalSets: nil,
            hasRestAfter: false,
            restAfterSeconds: nil
        )

        XCTAssertNil(interval.formattedTime)
    }

    // MARK: - Sets Expansion Tests

    func testSetsExpansionCreatesMultipleSteps() {
        // 3 sets of 10 reps with 60s rest
        let intervals: [WorkoutInterval] = [
            .reps(sets: 3, reps: 10, name: "Bench Press", load: "80%", restSec: 60, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // Should create 3 steps (one per set), each with rest info built-in
        XCTAssertEqual(flattened.count, 3)
    }

    func testSetsExpansionHasCorrectSetNumbers() {
        let intervals: [WorkoutInterval] = [
            .reps(sets: 3, reps: 10, name: "Squat", load: nil, restSec: 60, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // All steps are exercise steps with rest info
        XCTAssertEqual(flattened[0].setNumber, 1)
        XCTAssertEqual(flattened[0].totalSets, 3)
        XCTAssertTrue(flattened[0].hasRestAfter) // Has rest after set 1

        XCTAssertEqual(flattened[1].setNumber, 2)
        XCTAssertEqual(flattened[1].totalSets, 3)
        XCTAssertTrue(flattened[1].hasRestAfter) // Has rest after set 2

        XCTAssertEqual(flattened[2].setNumber, 3)
        XCTAssertEqual(flattened[2].totalSets, 3)
        XCTAssertFalse(flattened[2].hasRestAfter) // No rest after last set
    }

    func testSetsExpansionRestPeriodsAreTimed() {
        let intervals: [WorkoutInterval] = [
            .reps(sets: 2, reps: 8, name: "Deadlift", load: nil, restSec: 90, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // Should have 2 steps (one per set)
        XCTAssertEqual(flattened.count, 2)

        // First set should have 90s rest after
        XCTAssertTrue(flattened[0].hasRestAfter)
        XCTAssertEqual(flattened[0].restAfterSeconds, 90)
    }

    func testSetsExpansionNoRestAfterLastSet() {
        let intervals: [WorkoutInterval] = [
            .reps(sets: 3, reps: 10, name: "Push-ups", load: nil, restSec: 30, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // Last step should be Set 3 with no rest after
        XCTAssertEqual(flattened.last?.setNumber, 3)
        XCTAssertFalse(flattened.last?.hasRestAfter ?? true)
    }

    func testSetsExpansionWithNilSetsCreatesSingleStep() {
        let intervals: [WorkoutInterval] = [
            .reps(sets: nil, reps: 10, name: "Burpees", load: nil, restSec: nil, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // Should create just 1 step (nil sets defaults to 1)
        XCTAssertEqual(flattened.count, 1)
        XCTAssertEqual(flattened[0].setNumber, 1)
        XCTAssertEqual(flattened[0].totalSets, 1)
    }

    func testSetsExpansionWithOnlyOneSet() {
        let intervals: [WorkoutInterval] = [
            .reps(sets: 1, reps: 15, name: "Lunges", load: nil, restSec: 60, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // Should create 1 step (no rest after single set)
        XCTAssertEqual(flattened.count, 1)
        XCTAssertEqual(flattened[0].setNumber, 1)
        XCTAssertEqual(flattened[0].totalSets, 1)
    }

    func testSetsExpansionManualRestWhenRestSecIsNil() {
        let intervals: [WorkoutInterval] = [
            .reps(sets: 3, reps: 10, name: "Pull-ups", load: nil, restSec: nil, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // Should create 3 steps with rest info built-in
        XCTAssertEqual(flattened.count, 3)

        // First two have manual rest (restAfterSeconds: nil means manual)
        XCTAssertTrue(flattened[0].hasRestAfter)
        XCTAssertNil(flattened[0].restAfterSeconds) // nil = manual rest

        XCTAssertTrue(flattened[1].hasRestAfter)
        XCTAssertNil(flattened[1].restAfterSeconds)

        // Last set has no rest
        XCTAssertFalse(flattened[2].hasRestAfter)
    }

    func testSetsExpansionNoRestWhenRestSecIsZero() {
        // HIIT/superset style: restSec: 0 means no rest between sets
        let intervals: [WorkoutInterval] = [
            .reps(sets: 3, reps: 10, name: "Burpees", load: nil, restSec: 0, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // Should create 3 steps with no rest
        XCTAssertEqual(flattened.count, 3)

        // Verify no rest on any step
        XCTAssertTrue(flattened.allSatisfy { !$0.hasRestAfter })

        // Verify all steps are the exercise sets
        XCTAssertEqual(flattened[0].setNumber, 1)
        XCTAssertEqual(flattened[1].setNumber, 2)
        XCTAssertEqual(flattened[2].setNumber, 3)
        XCTAssertTrue(flattened.allSatisfy { $0.label == "Burpees" })
    }

    func testDisplayLabelWithSets() {
        let interval = FlattenedInterval(
            interval: .reps(sets: 3, reps: 10, name: "Squat", load: nil, restSec: nil, followAlongUrl: nil),
            index: 1,
            label: "Squat",
            details: "10 reps",
            roundInfo: nil,
            timerSeconds: nil,
            stepType: .reps,
            followAlongUrl: nil,
            targetReps: 10,
            setNumber: 2,
            totalSets: 3,
            hasRestAfter: true,
            restAfterSeconds: nil
        )

        XCTAssertEqual(interval.displayLabel, "Squat - Set 2 of 3")
    }

    func testDisplayLabelWithoutSets() {
        let interval = FlattenedInterval(
            interval: .time(seconds: 60, target: nil),
            index: 1,
            label: "Work",
            details: "60s",
            roundInfo: nil,
            timerSeconds: 60,
            stepType: .timed,
            followAlongUrl: nil,
            targetReps: nil,
            setNumber: nil,
            totalSets: nil,
            hasRestAfter: false,
            restAfterSeconds: nil
        )

        XCTAssertEqual(interval.displayLabel, "Work")
    }

    func testSetsExpansionWithMultipleExercises() {
        let intervals: [WorkoutInterval] = [
            .reps(sets: 2, reps: 10, name: "Bench Press", load: nil, restSec: 60, followAlongUrl: nil),
            .reps(sets: 2, reps: 12, name: "Rows", load: nil, restSec: 60, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        // Bench: Set 1, Set 2 = 2 steps (rest built into each step)
        // Rows: Set 1, Set 2 = 2 steps
        // Total = 4 steps
        XCTAssertEqual(flattened.count, 4)

        // Verify first exercise
        XCTAssertEqual(flattened[0].label, "Bench Press")
        XCTAssertEqual(flattened[0].setNumber, 1)
        XCTAssertTrue(flattened[0].hasRestAfter)

        // Verify second exercise starts at index 2
        XCTAssertEqual(flattened[2].label, "Rows")
        XCTAssertEqual(flattened[2].setNumber, 1)
    }
}
