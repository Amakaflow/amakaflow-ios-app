//
//  WatchActualsDraftBuilder.swift
//  AmakaFlow
//
//  AMA-2420 Phase 2 — seed Today Actuals fill-in draft from Watch standalone
//  strength set logs (correction surface = AMA-2387 Actuals).
//

import Foundation

enum WatchActualsDraftBuilder {
    /// Build an unverified fill-in session from a Watch summary.
    /// Prefer Library workout structure when available; otherwise use set logs alone.
    static func makeFillInSession(
        summary: StandaloneWorkoutSummary,
        libraryWorkout: Workout?
    ) -> ActualsFillInSession? {
        let setLogs = (summary.setLogs ?? []).map { log in
            SetLog(
                exerciseName: log.exerciseName,
                exerciseIndex: log.exerciseIndex,
                sets: log.sets.map {
                    SetEntry(
                        setNumber: $0.setNumber,
                        weight: $0.weight,
                        unit: $0.unit,
                        completed: $0.completed
                    )
                }
            )
        }

        var exercises: [ExerciseActual] = []
        if let libraryWorkout {
            exercises = StravaWorkoutStructureText.fillInExercises(from: libraryWorkout)
            overlay(setLogs: setLogs, onto: &exercises)
        }

        if exercises.isEmpty {
            exercises = exercisesFromSetLogs(setLogs)
        }

        guard !exercises.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        let when = formatter.string(from: summary.endDate).uppercased()

        return ActualsFillInSession(
            id: "watch-\(summary.workoutId)-\(Int(summary.endDate.timeIntervalSince1970))",
            title: summary.workoutName,
            subtitle: "APPLE WATCH · \(when)",
            exercises: exercises,
            verified: false
        )
    }

    private static func overlay(setLogs: [SetLog], onto exercises: inout [ExerciseActual]) {
        guard !setLogs.isEmpty else { return }
        // Last log wins on duplicate names (superset / rename edge cases).
        var byName: [String: SetLog] = [:]
        for log in setLogs {
            byName[log.exerciseName.lowercased()] = log
        }
        for index in exercises.indices {
            let key = exercises[index].name.lowercased()
            guard let log = byName[key] else { continue }
            let completed = log.sets.filter(\.completed)
            if let last = completed.last {
                if let weight = last.weight {
                    exercises[index].actualWeightKg = kilograms(weight: weight, unit: last.unit)
                }
                exercises[index].actualSets = max(completed.count, exercises[index].planned.sets)
            }
        }
    }

    private static func exercisesFromSetLogs(_ setLogs: [SetLog]) -> [ExerciseActual] {
        setLogs.sorted { $0.exerciseIndex < $1.exerciseIndex }.map { log in
            let completed = log.sets.filter(\.completed)
            let last = completed.last
            let weightKg = last.flatMap { kilograms(weight: $0.weight ?? 0, unit: $0.unit) }
            let setCount = max(completed.count, 1)
            return ExerciseActual(
                id: slug(log.exerciseName),
                name: log.exerciseName,
                planned: ExerciseActualPlanned(
                    sets: setCount,
                    reps: 1,
                    weightKg: weightKg,
                    note: nil
                ),
                confirmation: nil,
                actualSets: setCount,
                actualReps: 1,
                actualWeightKg: weightKg
            )
        }
    }

    private static func kilograms(weight: Double, unit: String?) -> Double? {
        guard weight > 0 else { return nil }
        let normalized = (unit ?? "lbs").lowercased()
        if normalized.contains("kg") {
            return weight
        }
        return weight * 0.45359237
    }

    private static func slug(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}
