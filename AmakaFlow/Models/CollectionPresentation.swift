//
//  CollectionPresentation.swift
//  AmakaFlow
//
//  AMA-2376: pure presentation helpers for Library collections grid.
//

import Foundation

enum CollectionPresentation {
    /// Sentinel id for derived Uncategorized folder (not a DB row).
    static let uncategorizedID = "uncategorized"

    /// Total duration for collection cards, e.g. `4H 10M`, `40M`, `TIME NOT SET`.
    /// AMA-2395: the seconds now come from `WorkoutDurationEstimator`, so the
    /// old `~` hedge on a made-up number is gone — an empty collection says so.
    static func formattedTotalDuration(seconds: Int) -> String {
        guard seconds > 0 else { return "TIME NOT SET" }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)H \(minutes)M"
        }
        return "\(minutes)M"
    }

    /// Collection/Uncategorized detail meta line, e.g.
    /// `6 WORKOUTS · ~4H 10M · RACE DAY - OCT 12` (note appended when present).
    static func detailMeta(workoutCount: Int, totalSeconds: Int, note: String?) -> String {
        let unit = workoutCount == 1 ? "WORKOUT" : "WORKOUTS"
        var line = "\(workoutCount) \(unit) · \(formattedTotalDuration(seconds: totalSeconds))"
        if let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedNote.isEmpty {
            line += " · \(trimmedNote)"
        }
        return line
    }

    /// Organize-mode header, e.g. `2 SELECTED · DESELECT ALL`.
    static func organizeHeader(selectedCount: Int) -> String {
        "\(selectedCount) SELECTED · DESELECT ALL"
    }

    /// Exact toast copy for a membership removal in Organize mode (Global Constraints).
    static func removedFromCollectionToast(collectionName: String) -> String {
        "removed from \(collectionName) — still in Library."
    }
}
