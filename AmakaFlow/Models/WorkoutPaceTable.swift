//
//  WorkoutPaceTable.swift
//  AmakaFlow
//
//  AMA-2395 — default pace table for distance steps in WorkoutDurationEstimator.
//  Seam for AMA-2387: swap defaults for the athlete's recent actuals without
//  changing call sites.
//

import Foundation

enum WorkoutPaceTable {
    /// Seconds for a distance step at v1 defaults (or future personal paces).
    static func seconds(forMeters meters: Double, exerciseName: String) -> Int {
        guard meters > 0 else { return 0 }
        let kind = WorkoutSportHonesty.machineKindKey(forExerciseName: exerciseName)
        let perUnit: (meters: Double, seconds: Double)
        switch kind {
        case "row":
            perUnit = (500, 120)
        case "ski":
            perUnit = (500, 130)
        case "bike":
            perUnit = (1000, 105)
        case "treadmill":
            perUnit = (1000, 330)
        default:
            if WorkoutSportHonesty.looksLikeRun(exerciseName) {
                perUnit = (1000, 330)
            } else {
                // Unknown machine / modality — 150s per 500 m.
                perUnit = (500, 150)
            }
        }
        return Int((meters / perUnit.meters * perUnit.seconds).rounded())
    }
}
