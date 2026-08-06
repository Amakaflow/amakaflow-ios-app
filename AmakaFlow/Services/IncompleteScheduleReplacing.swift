//
//  IncompleteScheduleReplacing.swift
//  AmakaFlow
//
//  AMA-2367 — discover/remove incomplete same-title plans around a new schedule.
//

import Foundation

/// AMA-2367 — discover/remove incomplete same-title plans around a new schedule.
///
/// Lookup is throwing so fetch failures surface to the caller. Removal is
/// intentionally separate and runs only after a successful save so a failed
/// schedule leaves existing plans intact.
protocol IncompleteScheduleReplacing: Sendable {
    func findIncompletePlans(titled title: String) async throws -> [WorkoutScheduleRow]
    func remove(rows: [WorkoutScheduleRow]) async
}

#if canImport(WorkoutKit)
@available(iOS 18.0, *)
@MainActor
final class LiveIncompleteScheduleReplacer: IncompleteScheduleReplacing, @unchecked Sendable {
    /// Shared across find → remove so `LiveWorkoutKitScheduler`'s plan cache stays warm.
    private let scheduler = LiveWorkoutKitScheduler()

    func findIncompletePlans(titled title: String) async throws -> [WorkoutScheduleRow] {
        let needle = WatchWorkoutTitlePolicy.normalized(title)
        guard !needle.isEmpty else { return [] }
        let rows = try await scheduler.fetchScheduledRows()
        return rows.filter { row in
            !row.isComplete && WatchWorkoutTitlePolicy.isSameScheduledTitle(row.title, title)
        }
    }

    func remove(rows: [WorkoutScheduleRow]) async {
        for row in rows {
            await scheduler.remove(row: row)
        }
    }

    static func normalizedTitle(_ title: String) -> String {
        WatchWorkoutTitlePolicy.normalized(title)
    }
}
#endif

enum IncompleteScheduleReplacerOverride {
    case automatic
    case injected(any IncompleteScheduleReplacing)
    case disabled
}
