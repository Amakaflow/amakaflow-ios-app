//
//  IncompleteScheduleReplacing.swift
//  AmakaFlow
//
//  AMA-2367 — remove incomplete same-title plans before adding a new schedule.
//

import Foundation

/// AMA-2367 — remove incomplete same-title plans before adding a new schedule.
protocol IncompleteScheduleReplacing: Sendable {
    func removeIncompletePlans(titled title: String) async
}

#if canImport(WorkoutKit)
@available(iOS 18.0, *)
struct LiveIncompleteScheduleReplacer: IncompleteScheduleReplacing {
    func removeIncompletePlans(titled title: String) async {
        let needle = Self.normalizedTitle(title)
        guard !needle.isEmpty else { return }
        let scheduler = LiveWorkoutKitScheduler()
        guard let rows = try? await scheduler.fetchScheduledRows() else { return }
        for row in rows where !row.isComplete {
            guard Self.normalizedTitle(row.title) == needle else { continue }
            await scheduler.remove(row: row)
        }
    }

    static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
#endif

enum IncompleteScheduleReplacerOverride {
    case automatic
    case injected(any IncompleteScheduleReplacing)
    case disabled
}
