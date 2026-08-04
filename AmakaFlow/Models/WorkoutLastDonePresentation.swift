//
//  WorkoutLastDonePresentation.swift
//  AmakaFlow
//
//  AMA-2376: format honest LAST DONE row from completion history.
//

import Foundation

enum WorkoutLastDonePresentation {
    /// Formats LAST DONE from list completions; returns nil when none match (hide row).
    /// Pass `rpe` only when loaded from completion detail — never invent from list model.
    static func line(
        from completions: [WorkoutCompletion],
        workoutId: String,
        rpe: Int? = nil
    ) -> String? {
        let matching = completions.filter { $0.workoutId == workoutId }
        guard !matching.isEmpty else { return nil }

        let latest = matching.max(by: { $0.startedAt < $1.startedAt })!
        let weekday = latest.startedAt.formatted(.dateTime.weekday(.abbreviated))
        let count = matching.count

        var segments = [weekday]
        if let rpe {
            segments.append("RPE \(rpe)")
        }
        segments.append("on \(latest.source.displayName)")
        segments.append("\(count)× total")

        return segments.joined(separator: " · ")
    }
}
