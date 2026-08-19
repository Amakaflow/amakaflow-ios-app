//
//  LogbookMetricStrip.swift
//  AmakaFlow
//
//  The TIME / DIST / CAL strip on a machine card. A pure function of one
//  entry — it never needed the view model's state, and moving it out keeps
//  LogbookViewModel.swift under the SwiftLint file_length limit as AMA-2473
//  adds the log-on-commit actions.
//

import Foundation

enum LogbookMetricStrip {
    static func refresh(_ entry: inout LogbookExerciseEntry) {
        guard entry.isMetric, let set = entry.sets.first else { return }
        let ghost = entry.ghosts.first
        let duration = set.durationSeconds ?? ghost?.durationSeconds ?? entry.plannedDurationSeconds
        let calories = set.calories ?? ghost?.calories ?? entry.plannedCalories
        let distance = set.distanceMeters
            ?? ghost?.distanceMeters
            ?? entry.plannedDistanceMeters.map(Double.init)
        entry.cardioStrip = LogbookCardioStrip(
            timeText: duration.map(LogbookMetricFormat.duration),
            distanceText: distance.map {
                LogbookMetricFormat.distance(
                    meters: $0, scale: entry.distanceScale, unit: .stored
                )
            },
            caloriesText: calories.map { "\($0)" },
            heartRateText: entry.cardioStrip?.heartRateText,
            sourceNote: entry.cardioStrip?.sourceNote
        )
    }
}
