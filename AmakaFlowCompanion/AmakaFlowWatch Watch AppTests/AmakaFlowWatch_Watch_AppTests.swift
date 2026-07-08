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

    @MainActor
    @Test("endSession persists workout by ending collection and finishing workout")
    func endSessionCallsEndCollectionAndFinishWorkout() async {
        final class MockWorkoutBuilder: WorkoutSessionBuilding {
            private(set) var endCollectionCalled = false
            private(set) var finishWorkoutCalled = false
            private(set) var callOrder: [String] = []

            func endCollection(at end: Date) async throws {
                endCollectionCalled = true
                callOrder.append("endCollection")
            }

            func finishWorkout() async throws -> HKWorkout? {
                finishWorkoutCalled = true
                callOrder.append("finishWorkout")
                return nil
            }
        }

        let mockBuilder = MockWorkoutBuilder()
        let manager = HealthKitWorkoutManager.shared
        manager.setBuilderForTesting(mockBuilder, isSessionActive: true)

        await manager.endSession()

        #expect(mockBuilder.endCollectionCalled, "endSession must call endCollection before closing the session")
        #expect(mockBuilder.finishWorkoutCalled, "endSession must call finishWorkout so completed workouts are persisted to HealthKit")
        #expect(
            mockBuilder.callOrder == ["endCollection", "finishWorkout"],
            "endSession must call endCollection before finishWorkout"
        )
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

// MARK: - AMA-1932: DayState legacy payload-shape compatibility

/// WatchConnectivityBridge deserializes DayState using convertFromSnakeCase.
/// AMA-1932: the phone historically pushed camelCase keys before snake_case was standardised.
/// Both shapes must decode correctly so watches running a mix of app versions stay functional.
struct DayStateLegacyPayloadCompatTests {

    private func decode(_ dict: [String: Any]) throws -> DayState {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DayState.self, from: data)
    }

    @Test("AMA-1932: snake_case payload (current format) decodes via convertFromSnakeCase")
    func snakeCasePayloadDecodes() throws {
        let payload: [String: Any] = [
            "date": "2026-05-01",
            "readiness_score": 80,
            "readiness_label": "ready",
            "sessions": [],
            "conflict_alert": NSNull()
        ]
        let dayState = try decode(payload)
        #expect(dayState.readinessScore == 80)
        #expect(dayState.readinessLabel == .ready)
        #expect(dayState.sessions.isEmpty)
        #expect(dayState.conflictAlert == nil)
    }

    @Test("AMA-1932: camelCase payload (legacy format) also decodes via convertFromSnakeCase")
    func camelCasePayloadDecodesAsLegacy() throws {
        // Prior to snake_case standardisation the phone sent camelCase keys directly.
        // convertFromSnakeCase passes already-camelCase keys through unchanged, so both shapes work.
        let payload: [String: Any] = [
            "date": "2026-05-01",
            "readinessScore": 80,
            "readinessLabel": "ready",
            "sessions": [],
            "conflictAlert": NSNull()
        ]
        let dayState = try decode(payload)
        #expect(dayState.readinessScore == 80)
        #expect(dayState.readinessLabel == .ready)
        #expect(dayState.sessions.isEmpty)
        #expect(dayState.conflictAlert == nil)
    }

    @Test("AMA-1932: legacy payload with sessions and conflict decodes all fields")
    func legacyPayloadWithSessionsAndConflict() throws {
        let payload: [String: Any] = [
            "date": "2026-05-01",
            "readiness_score": 55,
            "readiness_label": "moderate",
            "sessions": [
                [
                    "id": "s1",
                    "name": "Morning Run",
                    "scheduled_time": "07:00",
                    "sport": "running",
                    "duration_minutes": 45,
                    "is_completed": false,
                    "is_next": true
                ] as [String: Any]
            ],
            "conflict_alert": [
                "message": "Hard session tomorrow",
                "severity": "warning",
                "suggested_action": "Reduce intensity"
            ] as [String: Any]
        ]
        let dayState = try decode(payload)
        #expect(dayState.readinessLabel == .moderate)
        #expect(dayState.sessions.count == 1)
        #expect(dayState.sessions[0].name == "Morning Run")
        #expect(dayState.sessions[0].isNext == true)
        #expect(dayState.conflictAlert?.message == "Hard session tomorrow")
        #expect(dayState.conflictAlert?.severity == .warning)
    }

    @Test("AMA-1932: rest-day payload with empty sessions decodes correctly")
    func restDayPayloadDecodes() throws {
        let payload: [String: Any] = [
            "date": "2026-05-02",
            "readiness_score": 20,
            "readiness_label": "rest",
            "sessions": [],
            "conflict_alert": NSNull()
        ]
        let dayState = try decode(payload)
        #expect(dayState.readinessLabel == .rest)
        #expect(dayState.sessions.isEmpty)
    }
}
