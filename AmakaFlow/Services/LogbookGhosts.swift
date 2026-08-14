//
//  LogbookGhosts.swift
//  AmakaFlow
//
//  AMA-2426: ghost precedence — last ACTUALS > prescription; tap copies exactly.
//

import Foundation

enum LogbookGhosts {
    /// Resolve a single-set ghost. Actuals win; prescription only until actuals exist.
    static func resolve(
        lastActualWeightKg: Double?,
        lastActualReps: Int?,
        hasLastActual: Bool,
        plannedWeightKg: Double?,
        plannedReps: Int?
    ) -> LogbookGhost {
        if hasLastActual {
            return LogbookGhost(
                weightKg: lastActualWeightKg ?? plannedWeightKg,
                reps: lastActualReps ?? plannedReps,
                source: .lastActual
            )
        }
        return LogbookGhost(
            weightKg: plannedWeightKg,
            reps: plannedReps,
            source: .prescription
        )
    }

    /// Build per-set ghosts for an exercise. When set-level history exists, zip by index;
    /// otherwise repeat the exercise-level last actual / prescription for each set.
    static func ghosts(
        setCount: Int,
        planned: ExerciseActualPlanned,
        lastSetActuals: [SetActual]?,
        lastExerciseActual: ActualsGhostActual?
    ) -> [LogbookGhost] {
        guard setCount > 0 else { return [] }

        if let lastSets = lastSetActuals, !lastSets.isEmpty {
            let checked = lastSets.filter(\.isChecked).sorted { $0.index < $1.index }
            return (0..<setCount).map { index in
                if index < checked.count {
                    let set = checked[index]
                    return LogbookGhost(
                        weightKg: set.weightKg ?? planned.weightKg,
                        reps: set.reps ?? planned.reps,
                        source: .lastActual
                    )
                }
                if let last = checked.last {
                    return LogbookGhost(
                        weightKg: last.weightKg ?? planned.weightKg,
                        reps: last.reps ?? planned.reps,
                        source: .lastActual
                    )
                }
                return resolve(
                    lastActualWeightKg: nil,
                    lastActualReps: nil,
                    hasLastActual: false,
                    plannedWeightKg: planned.weightKg,
                    plannedReps: planned.reps
                )
            }
        }

        let hasActual = lastExerciseActual != nil
        let ghost = resolve(
            lastActualWeightKg: lastExerciseActual?.weightKg,
            lastActualReps: lastExerciseActual?.reps,
            hasLastActual: hasActual,
            plannedWeightKg: planned.weightKg,
            plannedReps: planned.reps
        )
        return Array(repeating: ghost, count: setCount)
    }

    /// Copy ghost values into a set's cells without checking ✓.
    static func copyGhost(into set: inout SetActual, ghost: LogbookGhost) {
        set.weightKg = ghost.weightKg
        set.reps = ghost.reps
        set.durationSeconds = ghost.durationSeconds
        set.calories = ghost.calories
        set.distanceMeters = ghost.distanceMeters
    }

    static func metricGhost(
        plannedDurationSeconds: Int?,
        plannedCalories: Int?,
        plannedDistanceMeters: Int?
    ) -> LogbookGhost {
        LogbookGhost(
            weightKg: nil,
            reps: nil,
            durationSeconds: plannedDurationSeconds,
            calories: plannedCalories,
            distanceMeters: plannedDistanceMeters.map(Double.init),
            source: .prescription
        )
    }
}
