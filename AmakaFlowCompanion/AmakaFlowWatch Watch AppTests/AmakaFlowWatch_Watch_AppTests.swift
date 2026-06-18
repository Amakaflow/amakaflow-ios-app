//
//  AmakaFlowWatch_Watch_AppTests.swift
//  AmakaFlowWatch Watch AppTests
//
//  Created by DAVID ANDREWS on 11/21/25.
//

import Foundation
import HealthKit
import Testing
@testable import AmakaFlowWatch_Watch_App

struct AmakaFlowWatch_Watch_AppTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @MainActor
    @Test("endSession persists workout by ending collection and finishing workout")
    func endSessionCallsEndCollectionAndFinishWorkout() async {
        final class MockWorkoutBuilder: WorkoutSessionBuilding {
            private(set) var endCollectionCalled = false
            private(set) var finishWorkoutCalled = false

            func endCollection(at end: Date) async throws {
                endCollectionCalled = true
            }

            func finishWorkout() async throws -> HKWorkout? {
                finishWorkoutCalled = true
                return nil
            }
        }

        let mockBuilder = MockWorkoutBuilder()
        let manager = HealthKitWorkoutManager.shared
        manager.setBuilderForTesting(mockBuilder, isSessionActive: true)

        await manager.endSession()

        #expect(mockBuilder.endCollectionCalled, "endSession must call endCollection before closing the session")
        #expect(mockBuilder.finishWorkoutCalled, "endSession must call finishWorkout so completed workouts are persisted to HealthKit")
    }

}

// MARK: - Issue 300: flattenWatchIntervals / duration regression tests

/// Rep steps must have timerSeconds = nil, confirming they cannot drive
/// elapsedSeconds via the countdown timer. Bug #300 used elapsedSeconds
/// (which never ticked for rep-only workouts) instead of wall-clock time.
struct FlattenWatchIntervalsTests {

    // A minimal strength workout: 3x5 push-ups with 60s rest between sets.
    private func pushUpWorkout() -> [WorkoutInterval] {
        [.reps(sets: 3, reps: 5, name: "Push-ups", load: nil, restSec: 60, followAlongUrl: nil)]
    }

    @Test("Rep steps have nil timerSeconds — they cannot drive elapsedSeconds")
    func repStepsHaveNilTimerSeconds() {
        let steps = flattenWatchIntervals(pushUpWorkout())
        #expect(steps.count == 3, "3 sets should produce 3 flattened steps")
        for step in steps {
            #expect(step.timerSeconds == nil, "rep step must have timerSeconds=nil; found \(String(describing: step.timerSeconds))")
            #expect(step.stepType == .reps, "all steps in a push-up workout must be .reps")
        }
    }

    @Test("Timed steps carry non-nil timerSeconds — they drive countdown timer")
    func timedStepsHaveTimerSeconds() {
        let intervals: [WorkoutInterval] = [
            .warmup(seconds: 120, target: nil),
            .time(seconds: 60, target: "Plank"),
            .cooldown(seconds: 90, target: nil)
        ]
        let steps = flattenWatchIntervals(intervals)
        for step in steps {
            #expect(step.timerSeconds != nil, "timed step must have non-nil timerSeconds; got nil for '\(step.label)'")
        }
    }

    /// Regression: durationSeconds in StandaloneWorkoutSummary must be computed
    /// from endDate - startDate, NOT from accumulated elapsedSeconds.
    /// For a 30-minute rep-only workout, elapsedSeconds stays ~0 (no timer ticks)
    /// but wall-clock time is 1800s.
    @Test("StandaloneWorkoutEngine duration helper uses wall-clock elapsed time")
    func durationFromDatesEqualsWallClock() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let wallClockDuration = StandaloneWorkoutEngine.summaryDurationSeconds(startDate: start, endDate: end)

        #expect(wallClockDuration == 1800, "Int(endDate - startDate) must equal 1800 for a 30-min workout")
        #expect(wallClockDuration > 0, "wall-clock duration must always be positive")
    }
}
