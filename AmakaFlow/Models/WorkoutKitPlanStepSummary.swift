//
//  WorkoutKitPlanStepSummary.swift
//  AmakaFlow
//
//  AMA-2360 — human-readable step lines from mapper WKPlanDTO for Apple preview.
//

import Foundation
import WorkoutKitSync

enum WorkoutKitPlanStepSummary {
    /// Short labels for preview (warmup / recovery / named work). Cap length for sheet.
    static func lines(from planJSON: Data, limit: Int = 12) -> [String] {
        guard let dto = try? WorkoutKitSync.default.parse(from: planJSON) else { return [] }
        var out: [String] = []
        for interval in dto.intervals {
            append(interval: interval, into: &out)
            if out.count >= limit { break }
        }
        if dto.intervals.count > limit {
            out.append("… +\(dto.intervals.count - limit) more")
        }
        return out
    }

    private static func append(interval: WKPlanDTO.Interval, into out: inout [String]) {
        switch interval {
        case .warmup(let seconds, _):
            out.append("Warm-up · \(seconds)s")
        case .cooldown(let seconds, _):
            out.append("Cool-down · \(seconds)s")
        case .repeatSet(let reps, let steps):
            out.append("Repeat ×\(reps)")
            for step in steps.prefix(6) {
                out.append("  · \(label(for: step))")
            }
            if steps.count > 6 {
                out.append("  · … +\(steps.count - 6) steps")
            }
        case .step(let step):
            out.append(label(for: step))
        }
    }

    private static func label(for step: WKPlanDTO.Interval.Step) -> String {
        let kind = step.kind.lowercased()
        if kind == "rest" || kind == "recovery" {
            if let seconds = step.seconds {
                return "Rest · \(seconds)s"
            }
            return "Rest · tap"
        }
        let name = step.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (name?.isEmpty == false) ? name! : kind
        if let reps = step.reps {
            return "\(base) · \(reps) reps"
        }
        if let seconds = step.seconds {
            return "\(base) · \(seconds)s"
        }
        return base
    }
}
