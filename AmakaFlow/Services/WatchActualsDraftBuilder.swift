//
//  WatchActualsDraftBuilder.swift
//  AmakaFlow
//
//  AMA-2420 Phase 2 — seed Today Actuals fill-in draft from Watch standalone
//  strength set logs (correction surface = AMA-2387 Actuals).
//

import Foundation

enum WatchActualsDraftBuilder {
    /// Stable Actuals fill-in id for a Watch standalone / passive summary.
    static func draftID(for summary: StandaloneWorkoutSummary) -> String {
        "watch-\(summary.workoutId)-\(Int(summary.endDate.timeIntervalSince1970))"
    }

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
                        completed: $0.completed,
                        detectionMethod: $0.detectionMethod,
                        reps: $0.reps
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

        // AMA-2420 passive free-capture — no set logs yet; seed a blank row for Fill in.
        if exercises.isEmpty {
            exercises = [
                ExerciseActual(
                    id: "exercise_1",
                    name: "Exercise 1",
                    planned: ExerciseActualPlanned(sets: 1, reps: 1, weightKg: nil, note: nil),
                    confirmation: nil,
                    actualSets: 1,
                    actualReps: 1,
                    actualWeightKg: nil
                )
            ]
        }

        guard !exercises.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        let when = formatter.string(from: summary.endDate).uppercased()

        let sport = resolvedSport(from: summary)
        let title = draftTitle(summary: summary, sport: sport)

        return ActualsFillInSession(
            id: draftID(for: summary),
            title: title,
            subtitle: "APPLE WATCH · \(when)",
            exercises: exercises,
            verified: false,
            sport: sport
        )
    }

    /// AMA-2428 — prefer wire `sport`; legacy names without sport default toward Strength.
    /// Unrecognized nonblank wire values fall back to Strength (explicit `other` stays Other).
    static func resolvedSport(from summary: StandaloneWorkoutSummary) -> WorkoutSport {
        if let raw = summary.sport, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return resolveWireSport(raw)
        }
        let name = summary.workoutName.lowercased()
        if name.contains("strength") { return .strength }
        if name.contains("mixed") || name.contains("hybrid") { return .mixed }
        let parsed = WorkoutSport.parse(summary.workoutName)
        return parsed == .other ? .strength : parsed
    }

    static func resolveWireSport(_ raw: String) -> WorkoutSport {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .strength }
        let parsed = WorkoutSport.parse(trimmed)
        if parsed != .other { return parsed }
        let token = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if token == "other" || token == "hyrox" {
            return .other
        }
        return .strength
    }

    static func draftTitle(summary: StandaloneWorkoutSummary, sport: WorkoutSport) -> String {
        if summary.sport != nil {
            return sport.displayName
        }
        let trimmed = summary.workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sport.displayName : trimmed
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
                if let reps = last.reps, reps > 0 {
                    exercises[index].actualReps = reps
                }
                if isAutoConfirmedAsPlanned(completed) {
                    exercises[index].confirmation = .asPlanned
                }
            }
        }
    }

    private static func exercisesFromSetLogs(_ setLogs: [SetLog]) -> [ExerciseActual] {
        setLogs.sorted { $0.exerciseIndex < $1.exerciseIndex }.map { log in
            let completed = log.sets.filter(\.completed)
            let last = completed.last
            let weightKg = last.flatMap { kilograms(weight: $0.weight ?? 0, unit: $0.unit) }
            let setCount = max(completed.count, 1)
            let reps = last?.reps.flatMap { $0 > 0 ? $0 : nil } ?? 1
            return ExerciseActual(
                id: slug(log.exerciseName),
                name: log.exerciseName,
                planned: ExerciseActualPlanned(
                    sets: setCount,
                    reps: reps,
                    weightKg: weightKg,
                    note: nil
                ),
                confirmation: isAutoConfirmedAsPlanned(completed) ? .asPlanned : nil,
                actualSets: setCount,
                actualReps: reps,
                actualWeightKg: weightKg
            )
        }
    }

    /// Require ≥1 completed set; empty `allSatisfy` would otherwise be vacuously true.
    private static func isAutoConfirmedAsPlanned(_ completed: [SetEntry]) -> Bool {
        !completed.isEmpty && completed.allSatisfy { $0.detectionMethod == "autoConfirmed" }
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
