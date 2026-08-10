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
/// leftover duplicates (races) while keeping the plan from the current confirm.
protocol IncompleteScheduleReplacing: Sendable {
    func findIncompletePlans(titled title: String) async throws -> [WorkoutScheduleRow]
    func remove(rows: [WorkoutScheduleRow]) async
}

extension IncompleteScheduleReplacing {
    /// AMA-2394 — after a successful schedule, keep one incomplete same-title plan.
    ///
    /// - Parameter keepingPlanID: Plan ID saved by the current confirmation (preferred keeper).
    /// - Parameter excluding: Pre-save replacement IDs that must not win as keeper.
    /// - Throws: When incomplete-plan lookup fails (caller must not treat as clean success).
    func removeDuplicateIncompletePlans(
        titled title: String,
        keepingPlanID: String?,
        excluding excludedPlanIDs: Set<String> = []
    ) async throws {
        let remaining = try await findIncompletePlans(titled: title)
        guard remaining.count > 1 else { return }

        let keeper = Self.selectKeeper(
            from: remaining,
            keepingPlanID: keepingPlanID,
            excluding: excludedPlanIDs
        )
        let toRemove = remaining.filter { $0.id != keeper.id }
        guard !toRemove.isEmpty else { return }
        await remove(rows: toRemove)
    }

    /// Prefer the confirm's saved plan ID. Fall back to newest schedule time, then
    /// lexicographic `planID` so equal dates are deterministic.
    static func selectKeeper( // swiftlint:disable:this trailing_closure
        from rows: [WorkoutScheduleRow],
        keepingPlanID: String?,
        excluding excludedPlanIDs: Set<String>
    ) -> WorkoutScheduleRow {
        if let keepingPlanID,
           let match = rows.first(where: \.id.planID == keepingPlanID) {
            return match
        }
        if let preferred = rows
            .filter { !excludedPlanIDs.contains($0.id.planID) }
            .min(by: IncompleteScheduleReplacerKeeper.isPreferredOrder) {
            return preferred
        }
        return rows.min(by: IncompleteScheduleReplacerKeeper.isPreferredOrder) ?? rows[0]
    }

    static func scheduleSortDate(_ row: WorkoutScheduleRow) -> Date {
        IncompleteScheduleReplacerKeeper.scheduleSortDate(row)
    }
}

/// Shared keeper / date ordering for AMA-2394 duplicate sweeps.
enum IncompleteScheduleReplacerKeeper {
    /// Newer schedule first; equal dates break ties on `planID` descending.
    static func isPreferredOrder(_ lhs: WorkoutScheduleRow, _ rhs: WorkoutScheduleRow) -> Bool {
        let leftDate = scheduleSortDate(lhs)
        let rightDate = scheduleSortDate(rhs)
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        return lhs.id.planID > rhs.id.planID
    }

    static func scheduleSortDate(_ row: WorkoutScheduleRow) -> Date {
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
