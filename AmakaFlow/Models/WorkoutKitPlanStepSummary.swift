//
//  WorkoutKitPlanStepSummary.swift
//  AmakaFlow
//
//  AMA-2360 — human-readable step lines from mapper WKPlanDTO for Apple preview.
//

import Foundation
import WorkoutKitSync

enum WorkoutKitPlanStepSummary {
    /// Short labels for preview (warmup / recovery / named work). `limit` is a hard cap.
    static func lines(from planJSON: Data, limit: Int = 12) -> [String] {
        guard limit > 0 else { return [] }
        guard let dto = try? WorkoutKitSync.default.parse(from: planJSON) else { return [] }
        var out: [String] = []
        let intervals = dto.intervals

        for (index, interval) in intervals.enumerated() {
            let room = limit - out.count
            guard room > 0 else { break }

            let laterLabelCount = intervals[(index + 1)..<intervals.count]
                .reduce(0) { $0 + labelCount(for: $1) }
            let remainingLabels = labelCount(for: interval) + laterLabelCount

            if room == 1, remainingLabels > 1 {
                out.append("… +\(remainingLabels) more")
                break
            }

            // Reserve one slot for a truncation marker when more labels may remain.
            let budget = laterLabelCount > 0 ? room - 1 : room
            if budget <= 0 {
                out.append("… +\(remainingLabels) more")
                break
            }

            let omittedNested = append(interval: interval, into: &out, budget: budget)
            if out.count > limit {
                out = Array(out.prefix(limit))
            }

            // Only stop early when this interval overflowed the budget (or we hit the hard cap).
            if omittedNested > 0 || out.count >= limit {
                let omitted = omittedNested + laterLabelCount
                if omitted > 0, out.count < limit {
                    out.append("… +\(omitted) more")
                }
                break
            }
        }
        return out
    }

    /// Approximate preview lines an interval would emit (uncapped).
    private static func labelCount(for interval: WKPlanDTO.Interval) -> Int {
        switch interval {
        case .warmup, .cooldown, .step:
            return 1
        case .repeatSet(_, let steps):
            return 1 + steps.count
        }
    }

    /// Appends up to `budget` lines. Returns how many nested step labels were omitted.
    @discardableResult
    private static func append(
        interval: WKPlanDTO.Interval,
        into out: inout [String],
        budget: Int
    ) -> Int {
        guard budget > 0 else { return labelCount(for: interval) }
        switch interval {
        case .warmup(let seconds, _):
            out.append("Warm-up · \(seconds)s")
            return 0
        case .cooldown(let seconds, _):
            out.append("Cool-down · \(seconds)s")
            return 0
        case .repeatSet(let reps, let steps):
            out.append("Repeat ×\(reps)")
            var used = 1
            for (stepIndex, step) in steps.enumerated() {
                guard used < budget else {
                    return steps.count - stepIndex
                }
                out.append("  · \(label(for: step))")
                used += 1
            }
            return 0
        case .step(let step):
            out.append(label(for: step))
            return 0
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
        let base: String
        if let name, !name.isEmpty {
            base = name
        } else {
            base = kind
        }
        if let reps = step.reps {
            return "\(base) · \(reps) reps"
        }
        if let seconds = step.seconds {
            return "\(base) · \(seconds)s"
        }
        return base
    }
}
