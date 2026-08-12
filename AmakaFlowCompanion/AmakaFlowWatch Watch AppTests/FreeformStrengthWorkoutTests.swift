//
//  FreeformStrengthWorkoutTests.swift
//  AmakaFlowWatch Watch AppTests
//
//  AMA-2420 — freeform Start template + plan-linked resolver.
//

@testable import AmakaFlowWatch_Watch_App
import Foundation
import Testing

struct FreeformStrengthWorkoutTests {
    @Test func freeformTemplateIsStrengthWithOpenSets() {
        let workout = FreeformStrengthWorkout.make(
            now: Date(timeIntervalSince1970: 1_776_000_000),
            uniqueSuffix: "test-a"
        )
        #expect(workout.sport == .strength)
        #expect(workout.name == "Strength")
        #expect(FreeformStrengthWorkout.isFreeformID(workout.id))
        #expect(workout.id.contains("1776000000"))
        #expect(workout.id.contains("test-a"))

        let steps = flattenWatchIntervals(workout.intervals)
        #expect(steps.count == FreeformStrengthWorkout.openSetCapacity)
        #expect(steps.allSatisfy { $0.stepType == .reps })
        #expect(steps.first?.label == "Exercise")
        #expect(steps.first?.setNumber == 1)
        #expect(steps.last?.setNumber == FreeformStrengthWorkout.openSetCapacity)
    }

    @Test func freeformIDsDifferForSameNow() {
        let now = Date(timeIntervalSince1970: 1_776_000_000)
        let first = FreeformStrengthWorkout.make(now: now)
        let second = FreeformStrengthWorkout.make(now: now)
        #expect(first.id != second.id)
        #expect(FreeformStrengthWorkout.isFreeformID(first.id))
        #expect(FreeformStrengthWorkout.isFreeformID(second.id))
    }

    @Test func planLinkedRequiresFlagAndStrengthSession() {
        let session = PlannedSession(
            id: "s1",
            name: "Upper Push",
            scheduledTime: nil,
            sport: "strength",
            durationMinutes: 45,
            isCompleted: false,
            isNext: true
        )
        let matched = Workout(
            id: "s1",
            name: "Upper Push",
            sport: .strength,
            duration: 1800,
            intervals: [
                .reps(sets: 3, reps: 8, name: "Bench", load: "60kg", restSec: 90, followAlongUrl: nil)
            ],
            source: .other
        )

        #expect(
            StrengthAutoCaptureStart.planLinkedWorkout(
                for: session,
                in: [matched],
                flagEnabled: false
            ) == nil
        )
        #expect(
            StrengthAutoCaptureStart.planLinkedWorkout(
                for: session,
                in: [matched],
                flagEnabled: true
            )?.id == "s1"
        )
    }

    @Test func planLinkedMatchesByNameWhenIDsDiffer() {
        let session = PlannedSession(
            id: "day-1",
            name: "Legs",
            scheduledTime: nil,
            sport: "traditional_strength_training",
            durationMinutes: nil,
            isCompleted: false,
            isNext: false
        )
        let workout = Workout(
            id: "lib-9",
            name: " Legs ",
            sport: .strength,
            duration: 0,
            intervals: [
                .reps(sets: 2, reps: 5, name: "Squat", load: nil, restSec: nil, followAlongUrl: nil)
            ],
            source: .other
        )

        let resolved = StrengthAutoCaptureStart.planLinkedWorkout(
            for: session,
            in: [workout],
            flagEnabled: true
        )
        #expect(resolved?.id == "lib-9")
    }

    @Test func planLinkedRejectsAmbiguousNameMatches() {
        let session = PlannedSession(
            id: "day-1",
            name: "Legs",
            scheduledTime: nil,
            sport: "strength",
            durationMinutes: nil,
            isCompleted: false,
            isNext: true
        )
        let first = Workout(
            id: "lib-a",
            name: "Legs",
            sport: .strength,
            duration: 0,
            intervals: [
                .reps(sets: 2, reps: 5, name: "Squat", load: nil, restSec: nil, followAlongUrl: nil)
            ],
            source: .other
        )
        let second = Workout(
            id: "lib-b",
            name: " legs ",
            sport: .strength,
            duration: 0,
            intervals: [
                .reps(sets: 3, reps: 8, name: "RDL", load: nil, restSec: nil, followAlongUrl: nil)
            ],
            source: .other
        )

        #expect(
            StrengthAutoCaptureStart.planLinkedWorkout(
                for: session,
                in: [first, second],
                flagEnabled: true
            ) == nil
        )
    }

    @Test func planLinkedSkipsCompletedAndNonStrength() {
        let completed = PlannedSession(
            id: "c1",
            name: "Done",
            scheduledTime: nil,
            sport: "strength",
            durationMinutes: nil,
            isCompleted: true,
            isNext: false
        )
        let run = PlannedSession(
            id: "r1",
            name: "Easy Run",
            scheduledTime: nil,
            sport: "running",
            durationMinutes: 30,
            isCompleted: false,
            isNext: true
        )
        let workout = Workout(
            id: "c1",
            name: "Done",
            sport: .strength,
            duration: 0,
            intervals: [
                .reps(sets: 1, reps: 5, name: "Curl", load: nil, restSec: nil, followAlongUrl: nil)
            ],
            source: .other
        )

        #expect(
            StrengthAutoCaptureStart.planLinkedWorkout(
                for: completed,
                in: [workout],
                flagEnabled: true
            ) == nil
        )
        #expect(
            StrengthAutoCaptureStart.planLinkedWorkout(
                for: run,
                in: [workout],
                flagEnabled: true
            ) == nil
        )
    }
}
