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
            let remainingIncludingThis = intervals.count - index
            if room == 1, remainingIncludingThis > 1 {
                out.append("… +\(remainingIncludingThis) more")
                break
            }
            let before = out.count
            append(interval: interval, into: &out, budget: room)
            // Hard cap even if append miscounted.
            if out.count > limit {
                out = Array(out.prefix(limit))
                break
            }
            if out.count == before {
                // Nothing added (budget too small) — stop.
                break
            }
        }
        return out
    }

    private static func append(
        interval: WKPlanDTO.Interval,
        into out: inout [String],
        budget: Int
    ) {
        guard budget > 0 else { return }
        switch interval {
        case .warmup(let seconds, _):
            out.append("Warm-up · \(seconds)s")
        case .cooldown(let seconds, _):
            out.append("Cool-down · \(seconds)s")
        case .repeatSet(let reps, let steps):
            out.append("Repeat ×\(reps)")
            var used = 1
            for (stepIndex, step) in steps.enumerated() {
                let left = budget - used
                guard left > 0 else { break }
                let remainingSteps = steps.count - stepIndex
                if left == 1, remainingSteps > 1 {
                    out.append("  · … +\(remainingSteps) steps")
                    break
                }
                out.append("  · \(label(for: step))")
                used += 1
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
