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

    /// Total duration for collection cards, e.g. `≈ 4H 10M`, `40M`, `TIME NOT SET`.
    /// AMA-2395: never emits the old `~1 MIN` / `~0H` hedge from bogus stored seconds.
    static func formattedTotalDuration(seconds: Int) -> String {
        guard seconds > 0 else { return "TIME NOT SET" }

        let hours = seconds / 3600
        let minutes = max(1, (seconds % 3600) / 60)

        if hours > 0 {
            let remainderMinutes = (seconds % 3600) / 60
            return "≈ \(hours)H \(remainderMinutes)M"
        }
        return "≈ \(minutes)M"
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

/// AMA-2416: Uncategorized library list prefers newest saved/imported workouts.
enum LibraryWorkoutOrdering {
    /// Newest `createdAt` first; missing dates sort last (stable by id).
    static func latestFirst(_ workouts: [Workout]) -> [Workout] {
        workouts.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (leftDate?, rightDate?):
                if leftDate != rightDate { return leftDate > rightDate }
                return lhs.id > rhs.id
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.id > rhs.id
            }
        }
    }
}
