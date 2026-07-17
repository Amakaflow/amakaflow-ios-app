//
//  WorkoutCompletionDetail+TodayDiary.swift
//  AmakaFlow
//
//  AMA-2289: Fixture detail payloads for Today diary items.
//

import Foundation

extension WorkoutCompletionDetail {
    /// Strava-imported lunch run for Today diary fixtures (no structure editor).
    static var garminTodaySample: WorkoutCompletionDetail {
        let window = WorkoutCompletion.todayDiarySampleData().first {
            $0.id == "today-lunch-run"
        }
        let startedAt = window?.startedAt ?? Date()
        let endedAt = window?.endedAt ?? startedAt.addingTimeInterval(59 * 60)
        return WorkoutCompletionDetail(
            id: "today-lunch-run",
            workoutName: "Lunch Run",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 59 * 60,
            avgHeartRate: 143,
            maxHeartRate: 165,
            minHeartRate: 110,
            activeCalories: 677,
            totalCalories: 710,
            steps: 9800,
            distanceMeters: 8200,
            source: .garmin,
            deviceInfo: CompletionDeviceInfo(model: "Forerunner 965", platform: "garmin", osVersion: nil),
            heartRateSamples: nil,
            syncedToStrava: true,
            stravaActivityId: "strava-fixture-lunch-run",
            workoutId: "workout-lunch-run",
            workoutStructure: [
                .warmup(seconds: 300, target: "Easy"),
                .distance(meters: 7200, target: "Z2"),
                .cooldown(seconds: 300, target: "Walk")
            ]
        )
    }

    /// Sparse Strava lunch workout — needs activity mapping (dd-today-dark.png).
    static var phoneTodaySample: WorkoutCompletionDetail {
        let window = WorkoutCompletion.todayDiarySampleData().first {
            $0.id == "today-lunch-workout"
        }
        let startedAt = window?.startedAt ?? Date()
        let endedAt = window?.endedAt ?? startedAt.addingTimeInterval(8 * 60)
        return WorkoutCompletionDetail(
            id: "today-lunch-workout",
            workoutName: "Lunch Workout",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 8 * 60,
            avgHeartRate: nil,
            maxHeartRate: nil,
            minHeartRate: nil,
            activeCalories: 50,
            totalCalories: 55,
            steps: nil,
            distanceMeters: nil,
            source: .manual,
            deviceInfo: CompletionDeviceInfo(model: "iPhone", platform: "ios", osVersion: "18.0"),
            heartRateSamples: nil,
            syncedToStrava: true,
            stravaActivityId: "strava-fixture-lunch-workout",
            workoutId: nil,
            workoutStructure: nil
        )
    }

    /// AMA-2290: live phone completion recorded during a fixture session.
    static func phoneLiveSample(
        id: String,
        from completion: WorkoutCompletion?,
        setLogs: [SetLog]?
    ) -> WorkoutCompletionDetail {
        let startedAt = completion?.startedAt ?? Date()
        let endedAt = completion?.endedAt ?? startedAt.addingTimeInterval(
            TimeInterval(completion?.durationSeconds ?? 1800)
        )
        let structure: [WorkoutInterval]? = setLogs?.map { log in
            .reps(
                sets: log.sets.count,
                reps: 0,
                name: log.exerciseName,
                load: log.sets.compactMap(\.weight).first.map { "\($0)" },
                restSec: nil,
                followAlongUrl: nil
            )
        }
        return WorkoutCompletionDetail(
            id: id,
            workoutName: completion?.workoutName ?? "Phone Strength",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: completion?.durationSeconds ?? 1800,
            avgHeartRate: completion?.avgHeartRate,
            maxHeartRate: completion?.maxHeartRate,
            minHeartRate: nil,
            activeCalories: completion?.activeCalories,
            totalCalories: completion?.activeCalories,
            steps: nil,
            distanceMeters: nil,
            source: .phone,
            deviceInfo: CompletionDeviceInfo(model: "iPhone", platform: "ios", osVersion: nil),
            heartRateSamples: nil,
            syncedToStrava: false,
            stravaActivityId: nil,
            workoutId: completion?.workoutId,
            workoutStructure: structure ?? [
                .reps(sets: 3, reps: 8, name: "Strength", load: nil, restSec: nil, followAlongUrl: nil)
            ]
        )
    }
}
