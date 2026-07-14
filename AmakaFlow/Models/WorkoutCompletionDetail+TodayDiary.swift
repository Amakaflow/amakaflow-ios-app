//
//  WorkoutCompletionDetail+TodayDiary.swift
//  AmakaFlow
//
//  AMA-2289: Fixture detail payloads for Today diary items.
//

import Foundation

extension WorkoutCompletionDetail {
    /// Garmin-synced run for Today diary fixtures (no structure editor).
    static var garminTodaySample: WorkoutCompletionDetail {
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        return WorkoutCompletionDetail(
            id: "today-garmin-run",
            workoutName: "Morning Easy Run",
            startedAt: start,
            endedAt: now.addingTimeInterval(-1800),
            durationSeconds: 1800,
            avgHeartRate: 148,
            maxHeartRate: 165,
            minHeartRate: 110,
            activeCalories: 310,
            totalCalories: 340,
            steps: 6200,
            distanceMeters: 5200,
            source: .garmin,
            deviceInfo: CompletionDeviceInfo(model: "Forerunner 965", platform: "garmin", osVersion: nil),
            heartRateSamples: nil,
            syncedToStrava: true,
            stravaActivityId: "strava-fixture-run",
            workoutId: "workout-garmin-run",
            workoutStructure: [
                .warmup(seconds: 300, target: "Easy"),
                .distance(meters: 4000, target: "Z2"),
                .cooldown(seconds: 300, target: "Walk")
            ]
        )
    }

    /// Phone-completed strength for Today diary fixtures.
    static var phoneTodaySample: WorkoutCompletionDetail {
        let now = Date()
        let start = now.addingTimeInterval(-7200)
        return WorkoutCompletionDetail(
            id: "today-phone-strength",
            workoutName: "Upper Body Strength",
            startedAt: start,
            endedAt: now.addingTimeInterval(-5400),
            durationSeconds: 1800,
            avgHeartRate: 118,
            maxHeartRate: 145,
            minHeartRate: 90,
            activeCalories: 245,
            totalCalories: 270,
            steps: nil,
            distanceMeters: nil,
            source: .phone,
            deviceInfo: CompletionDeviceInfo(model: "iPhone", platform: "ios", osVersion: "18.0"),
            heartRateSamples: nil,
            syncedToStrava: false,
            stravaActivityId: nil,
            workoutId: "workout-phone-strength",
            workoutStructure: [
                .reps(sets: 3, reps: 10, name: "Bench Press", load: "135 lb", restSec: 90, followAlongUrl: nil),
                .reps(sets: 3, reps: 12, name: "Rows", load: "95 lb", restSec: 75, followAlongUrl: nil)
            ]
        )
    }
}
