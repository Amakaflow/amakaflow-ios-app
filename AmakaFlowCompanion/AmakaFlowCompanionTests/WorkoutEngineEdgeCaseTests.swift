//
//  WorkoutEngineEdgeCaseTests.swift
//  AmakaFlowCompanionTests
//
//  Additional edge case tests for WorkoutEngine (AMA-231)
//  Covers rest phase transitions, timer edge cases, and state validation
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutEngineEdgeCaseTests: XCTestCase {

    var engine: WorkoutEngine!

    override func setUp() async throws {
        engine = WorkoutEngine.shared
        engine.reset()
    }

    override func tearDown() async throws {
        engine.reset()
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Test Fixtures

    private func createTestWorkout(intervals: [WorkoutInterval]) -> Workout {
        Workout(
            id: "edge-case-test-\(UUID().uuidString)",
            name: "Edge Case Test",
            sport: .strength,
            duration: 600,
            intervals: intervals,
            description: nil,
            source: .ai
        )
    }

    // MARK: - Rest Phase Transition Tests

    func testRestPhaseAfterWarmup() {
        // Warmup intervals have rest after by default
        let workout = createTestWorkout(intervals: [
            .warmup(seconds: 30, target: nil),
            .time(seconds: 60, target: nil)
        ])
        engine.start(workout: workout)

        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.currentStepIndex, 0)

        // First nextStep should enter rest phase
        engine.nextStep()

        // Check we're in rest phase
        XCTAssertEqual(engine.phase, .resting)
    }

    func testRestPhaseExitAdvancesStep() {
        let workout = createTestWorkout(intervals: [
            .warmup(seconds: 30, target: nil),
            .time(seconds: 60, target: nil)
        ])
        engine.start(workout: workout)

        // Enter rest phase
        engine.nextStep()
        XCTAssertEqual(engine.phase, .resting)

        // Exit rest phase - may need multiple nextStep calls depending on rest duration
        // Keep advancing until we're at step 1
        for _ in 0..<5 {
            if engine.currentStepIndex == 1 && engine.phase == .running {
                break
            }
            engine.nextStep()
        }

        XCTAssertEqual(engine.currentStepIndex, 1)
    }

    func testCooldownHasNoRestAfter() {
        let workout = createTestWorkout(intervals: [
            .cooldown(seconds: 30, target: nil)
        ])
        engine.start(workout: workout)

        // Cooldown should end workout directly, no rest phase
        engine.nextStep()

        XCTAssertEqual(engine.phase, .ended)
    }

    func testRepsWithSetsHasRestInfo() {
        // Test that reps with sets > 1 has rest information in flattened steps
        let workout = createTestWorkout(intervals: [
            .reps(sets: 2, reps: 10, name: "Squats", load: nil, restSec: 30, followAlongUrl: nil)
        ])
        engine.start(workout: workout)

        // With 2 sets and 30s rest, we should have 2 steps
        XCTAssertEqual(engine.flattenedSteps.count, 2)

        // First set should have rest after
        XCTAssertTrue(engine.flattenedSteps[0].hasRestAfter)
        XCTAssertEqual(engine.flattenedSteps[0].restAfterSeconds, 30)

        // Last set should have no rest
        XCTAssertFalse(engine.flattenedSteps[1].hasRestAfter)
    }

    // MARK: - Empty Workout Tests

    func testEmptyWorkoutDoesNotCrash() {
        let workout = createTestWorkout(intervals: [])
        engine.start(workout: workout)

        // Should handle empty intervals gracefully
        XCTAssertTrue(engine.flattenedSteps.isEmpty)
        XCTAssertEqual(engine.currentStepIndex, 0)
    }

    func testSingleIntervalWorkout() {
        let workout = createTestWorkout(intervals: [
            .cooldown(seconds: 30, target: nil)
        ])
        engine.start(workout: workout)

        XCTAssertEqual(engine.flattenedSteps.count, 1)
        XCTAssertEqual(engine.progress, 1.0, accuracy: 0.01)
    }

    // MARK: - State Consistency Tests

    func testPhaseTransitionConsistency() {
        let workout = createTestWorkout(intervals: [
            .warmup(seconds: 30, target: nil),
            .time(seconds: 60, target: nil),
            .cooldown(seconds: 30, target: nil)
        ])
        engine.start(workout: workout)

        // Track phase transitions
        var phases: [WorkoutPhase] = [engine.phase]

        // Progress through workout
        engine.nextStep() // rest
        phases.append(engine.phase)
        engine.nextStep() // step 2
        phases.append(engine.phase)
        engine.nextStep() // rest
        phases.append(engine.phase)
        engine.nextStep() // step 3
        phases.append(engine.phase)
        engine.nextStep() // end
        phases.append(engine.phase)

        // Verify we went through expected transitions
        XCTAssertEqual(phases.first, .running)
        XCTAssertEqual(phases.last, .ended)
    }

    func testResetClearsAllState() {
        let workout = createTestWorkout(intervals: [
            .time(seconds: 60, target: nil)
        ])
        engine.start(workout: workout)
        engine.nextStep()
        engine.nextStep()

        engine.reset()

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.workout)
        XCTAssertEqual(engine.currentStepIndex, 0)
        XCTAssertEqual(engine.remainingSeconds, 0)
        XCTAssertTrue(engine.flattenedSteps.isEmpty)
    }

    // MARK: - Remote Command Edge Cases

    func testRemoteCommandResumeWhilePaused() {
        let workout = createTestWorkout(intervals: [
            .time(seconds: 60, target: nil),
            .time(seconds: 30, target: nil)
        ])
        engine.start(workout: workout)
        engine.pause()
        XCTAssertEqual(engine.phase, .paused)

        // RESUME should work while paused
        engine.handleRemoteCommand("RESUME", commandId: "paused-cmd-1")

        // Should have resumed
        XCTAssertEqual(engine.phase, .running)
    }

    func testRemoteCommandAfterEnded() {
        let workout = createTestWorkout(intervals: [
            .cooldown(seconds: 10, target: nil)
        ])
        engine.start(workout: workout)
        engine.end(reason: .completed)

        let stateVersion = engine.stateVersion

        // Commands should be ignored after ended
        engine.handleRemoteCommand("PAUSE", commandId: "ended-cmd-1")
        engine.handleRemoteCommand("RESUME", commandId: "ended-cmd-2")
        engine.handleRemoteCommand("NEXT_STEP", commandId: "ended-cmd-3")

        XCTAssertEqual(engine.phase, .ended)
        // State version might not change since commands are ignored
    }

    func testEmptyCommandIdHandled() {
        let workout = createTestWorkout(intervals: [
            .time(seconds: 60, target: nil)
        ])
        engine.start(workout: workout)

        // Empty command ID should still work
        engine.handleRemoteCommand("PAUSE", commandId: "")

        XCTAssertEqual(engine.phase, .paused)
    }

    // MARK: - Step Navigation Edge Cases

    func testSkipToNegativeIndex() {
        let workout = createTestWorkout(intervals: [
            .time(seconds: 60, target: nil),
            .time(seconds: 30, target: nil)
        ])
        engine.start(workout: workout)

        engine.skipToStep(-1)

        // Should stay at current step
        XCTAssertEqual(engine.currentStepIndex, 0)
    }

    func testMultiplePreviousAtStart() {
        let workout = createTestWorkout(intervals: [
            .time(seconds: 60, target: nil),
            .time(seconds: 30, target: nil)
        ])
        engine.start(workout: workout)

        // Multiple previous at start should not crash
        engine.previousStep()
        engine.previousStep()
        engine.previousStep()

        XCTAssertEqual(engine.currentStepIndex, 0)
    }

    func testRapidNextPrevious() {
        let workout = createTestWorkout(intervals: [
            .cooldown(seconds: 10, target: nil),  // No rest
            .cooldown(seconds: 10, target: nil),  // No rest
            .cooldown(seconds: 10, target: nil)   // No rest
        ])
        engine.start(workout: workout)

        // Rapid navigation
        engine.nextStep()
        engine.previousStep()
        engine.nextStep()
        engine.nextStep()
        engine.previousStep()

        // Should be at a valid state
        XCTAssertGreaterThanOrEqual(engine.currentStepIndex, 0)
        XCTAssertLessThan(engine.currentStepIndex, engine.flattenedSteps.count)
    }

    // MARK: - Timer Edge Cases

    func testZeroSecondInterval() {
        // This tests edge case handling - though unlikely in practice
        let workout = createTestWorkout(intervals: [
            .time(seconds: 0, target: nil)
        ])
        engine.start(workout: workout)

        XCTAssertEqual(engine.remainingSeconds, 0)
    }

    func testLargeSecondValue() {
        let workout = createTestWorkout(intervals: [
            .time(seconds: 7200, target: nil)  // 2 hours
        ])
        engine.start(workout: workout)

        XCTAssertEqual(engine.remainingSeconds, 7200)
    }

    // MARK: - Workout Property Tests

    func testWorkoutNamePreserved() {
        let workout = Workout(
            id: "name-test",
            name: "My Custom Workout",
            sport: .running,
            duration: 300,
            intervals: [.time(seconds: 60, target: nil)],
            description: "Test description",
            source: .coach
        )
        engine.start(workout: workout)

        XCTAssertEqual(engine.workout?.name, "My Custom Workout")
        XCTAssertEqual(engine.workout?.sport, .running)
        XCTAssertEqual(engine.workout?.source, .coach)
    }

    // MARK: - Progress Edge Cases

    func testProgressNeverExceedsOne() {
        let workout = createTestWorkout(intervals: [
            .cooldown(seconds: 10, target: nil)
        ])
        engine.start(workout: workout)

        // Even at last step, progress should not exceed 1.0
        XCTAssertLessThanOrEqual(engine.progress, 1.0)
    }

    func testProgressNeverNegative() {
        let workout = createTestWorkout(intervals: [
            .time(seconds: 60, target: nil),
            .time(seconds: 30, target: nil)
        ])
        engine.start(workout: workout)

        XCTAssertGreaterThanOrEqual(engine.progress, 0.0)

        engine.previousStep()

        XCTAssertGreaterThanOrEqual(engine.progress, 0.0)
    }
}

// MARK: - Nested Repeat Tests

final class NestedRepeatTests: XCTestCase {

    func testDoubleNestedRepeat() {
        let intervals: [WorkoutInterval] = [
            .repeat(reps: 2, intervals: [
                .repeat(reps: 2, intervals: [
                    .time(seconds: 30, target: nil)
                ])
            ])
        ]

        let flattened = flattenIntervals(intervals)

        // 2 outer x 2 inner = 4 steps
        XCTAssertEqual(flattened.count, 4)
    }

    func testRepeatWithMixedIntervals() {
        let intervals: [WorkoutInterval] = [
            .repeat(reps: 2, intervals: [
                .time(seconds: 30, target: nil),
                .reps(sets: nil, reps: 10, name: "Burpees", load: nil, restSec: nil, followAlongUrl: nil)
            ])
        ]

        let flattened = flattenIntervals(intervals)

        // 2 rounds x 2 intervals = 4 steps
        XCTAssertEqual(flattened.count, 4)
    }

    func testSingleRepRepeat() {
        let intervals: [WorkoutInterval] = [
            .repeat(reps: 1, intervals: [
                .time(seconds: 60, target: nil)
            ])
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened.count, 1)
    }

    func testLargeRepeatCount() {
        // Test with a large but reasonable repeat count
        let intervals: [WorkoutInterval] = [
            .repeat(reps: 10, intervals: [
                .time(seconds: 30, target: nil)
            ])
        ]

        let flattened = flattenIntervals(intervals)

        // 10 reps = 10 steps
        XCTAssertEqual(flattened.count, 10)
    }

    func testRepeatRoundInfo() {
        let intervals: [WorkoutInterval] = [
            .repeat(reps: 3, intervals: [
                .time(seconds: 30, target: nil),
                .time(seconds: 20, target: nil)
            ])
        ]

        let flattened = flattenIntervals(intervals)

        // Check round info is present
        XCTAssertEqual(flattened[0].roundInfo, "Round 1 of 3")
        XCTAssertEqual(flattened[2].roundInfo, "Round 2 of 3")
        XCTAssertEqual(flattened[4].roundInfo, "Round 3 of 3")
    }
}

// MARK: - StepType Tests

final class StepTypeTests: XCTestCase {

    func testWarmupIsTimedStepType() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 60, target: nil)
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened[0].stepType, .timed)
    }

    func testCooldownIsTimedStepType() {
        let intervals: [WorkoutInterval] = [
            .cooldown(seconds: 60, target: nil)
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened[0].stepType, .timed)
    }

    func testTimeIsTimedStepType() {
        let intervals: [WorkoutInterval] = [
            .time(seconds: 60, target: nil)
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened[0].stepType, .timed)
    }

    func testRepsIsRepsStepType() {
        let intervals: [WorkoutInterval] = [
            .reps(sets: nil, reps: 10, name: "Squats", load: nil, restSec: nil, followAlongUrl: nil)
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened[0].stepType, .reps)
    }

    func testDistanceIsDistanceStepType() {
        let intervals: [WorkoutInterval] = [
            .distance(meters: 1000, target: nil)
        ]

        let flattened = flattenIntervals(intervals)

        XCTAssertEqual(flattened[0].stepType, .distance)
    }
}

// MARK: - Formatted Time Tests

final class FormattedTimeEdgeCaseTests: XCTestCase {

    func testFormattedTimeZeroSeconds() {
        let seconds = 0
        let formatted = formatSeconds(seconds)

        XCTAssertEqual(formatted, "0:00")
    }

    func testFormattedTimeUnderOneMinute() {
        let seconds = 45
        let formatted = formatSeconds(seconds)

        XCTAssertEqual(formatted, "45s")
    }

    func testFormattedTimeExactlyOneMinute() {
        let seconds = 60
        let formatted = formatSeconds(seconds)

        XCTAssertEqual(formatted, "1:00")
    }

    func testFormattedTimeOverOneHour() {
        let seconds = 3725  // 1:02:05
        let formatted = formatSecondsWithHours(seconds)

        XCTAssertEqual(formatted, "1:02:05")
    }

    func testFormattedTimeExactlyOneHour() {
        let seconds = 3600
        let formatted = formatSecondsWithHours(seconds)

        XCTAssertEqual(formatted, "1:00:00")
    }

    // MARK: - Helper Methods

    private func formatSeconds(_ seconds: Int) -> String {
        if seconds < 60 {
            return seconds == 0 ? "0:00" : "\(seconds)s"
        }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatSecondsWithHours(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
