//
//  IncompleteScheduleReplacing.swift
//  AmakaFlow
//
//  AMA-2367 — discover/remove incomplete same-title plans around a new schedule.
//

import Foundation

/// AMA-2367 / AMA-2394 — discover/remove incomplete same-title plans around a new schedule.
///
/// Lookup is throwing so fetch failures surface to the caller. Removal of the
/// pre-save replacement set runs only after a successful save so a failed
/// schedule leaves existing plans intact. A post-save sweep may still remove
/// leftover duplicates (races) while keeping the newest incomplete same-title.
protocol IncompleteScheduleReplacing: Sendable {
    func findIncompletePlans(titled title: String) async throws -> [WorkoutScheduleRow]
    func remove(rows: [WorkoutScheduleRow]) async
}

extension IncompleteScheduleReplacing {
    /// AMA-2394 — after a successful schedule, keep one incomplete same-title plan.
    /// Prefers a plan whose id was not in `excludedPlanIDs` (the newly saved one).
    func removeDuplicateIncompletePlans(
        titled title: String,
        excluding excludedPlanIDs: Set<String> = []
    ) async {
        guard let remaining = try? await findIncompletePlans(titled: title), remaining.count > 1 else {
            return
        }
        let sorted = remaining.sorted { lhs, rhs in
            Self.scheduleSortDate(lhs) > Self.scheduleSortDate(rhs)
        }
        let keeper = sorted.first { !excludedPlanIDs.contains($0.id.planID) } ?? sorted[0]
        let toRemove = sorted.filter { $0.id != keeper.id }
        guard !toRemove.isEmpty else { return }
        await remove(rows: toRemove)
    }

    private static func scheduleSortDate(_ row: WorkoutScheduleRow) -> Date {
        if let scheduledAt = row.scheduledAt {
            return scheduledAt
        }
        return Calendar.current.date(from: row.dateComponents) ?? .distantPast
    }
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
