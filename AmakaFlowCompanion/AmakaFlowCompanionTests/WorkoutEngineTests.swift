//
//  WorkoutEngineTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for WorkoutEngine state machine
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutEngineTests: XCTestCase {

    var engine: WorkoutEngine!

    override func setUp() async throws {
        engine = WorkoutEngine.shared
        engine.reset()
    }

    override func tearDown() async throws {
        engine.reset()
    }

    // MARK: - Test Fixtures

    private func createTestWorkout(intervals: [WorkoutInterval]? = nil) -> Workout {
        Workout(
            id: "test-workout-1",
            name: "Test Workout",
            sport: .strength,
            duration: 600,
            intervals: intervals ?? [
                .warmup(seconds: 30, target: "Easy pace"),
                .reps(reps: 10, name: "Push-ups", load: nil, restSec: 15, followAlongUrl: nil),
                .time(seconds: 60, target: "Plank hold"),
                .cooldown(seconds: 30, target: nil)
            ],
            description: "A test workout",
            source: .coach
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
            .reps(reps: 10, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil)
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

        engine.nextStep()

        XCTAssertEqual(engine.currentStepIndex, 1)
    }

    func testNextStepAtEndEndsWorkout() {
        let workout = createTestWorkout(intervals: [
            .warmup(seconds: 10, target: nil)
        ])
        engine.start(workout: workout)

        engine.nextStep()

        XCTAssertEqual(engine.phase, .ended)
    }

    func testPreviousStep() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
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
        let workout = createTestWorkout()
        engine.start(workout: workout)
        engine.nextStep()
        engine.nextStep()

        // 3 of 4 steps = 0.75
        XCTAssertEqual(engine.progress, 0.75, accuracy: 0.01)
    }

    func testFormattedStepProgress() {
        let workout = createTestWorkout()
        engine.start(workout: workout)

        XCTAssertEqual(engine.formattedStepProgress, "1 of 4")

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
                .reps(reps: 10, name: "Push-ups", load: nil, restSec: nil, followAlongUrl: nil),
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
                .reps(reps: 5, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil)
            ])
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened[0].roundInfo, "Round 1 of 2")
        XCTAssertEqual(flattened[1].roundInfo, "Round 2 of 2")
    }

    func testFlattenedIntervalStepType() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 30, target: nil),
            .reps(reps: 10, name: "Lunges", load: nil, restSec: nil, followAlongUrl: nil),
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

        engine.handleRemoteCommand("NEXT_STEP", commandId: "cmd-3")

        XCTAssertEqual(engine.currentStepIndex, 1)
    }

    func testHandleRemoteCommandPreviousStep() {
        let workout = createTestWorkout()
        engine.start(workout: workout)
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
            targetReps: nil
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
            targetReps: nil
        )

        XCTAssertEqual(interval.formattedTime, "45s")
    }

    func testFormattedTimeNilForNonTimed() {
        let interval = FlattenedInterval(
            interval: .reps(reps: 10, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil),
            index: 1,
            label: "Squats",
            details: "10 reps",
            roundInfo: nil,
            timerSeconds: nil,
            stepType: .reps,
            followAlongUrl: nil,
            targetReps: 10
        )

        XCTAssertNil(interval.formattedTime)
    }
}
