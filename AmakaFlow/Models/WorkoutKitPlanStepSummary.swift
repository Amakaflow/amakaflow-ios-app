//
//  WorkoutKitPlanStepSummary.swift
//  AmakaFlow
//
//  AMA-2360 — human-readable step lines from mapper WKPlanDTO for Apple preview.
//  AMA-2371 — banded `sections(from:)` for the Runna-style Apple Watch preview
//  sheet; rest becomes a chip instead of a monospace dump line.
//

import Foundation
import WorkoutKitSync

// MARK: - Section banding (AMA-2371)

/// One colored band on the Apple Watch preview sheet (e.g. "WARM-UP", "WORK").
enum PreviewBandKind: Equatable {
    case warmup
    case work
    case cooldown

    var label: String {
        switch self {
        case .warmup: return "WARM-UP"
        case .work: return "WORK"
        case .cooldown: return "COOL-DOWN"
        }
    }
}

/// A single row inside a `PreviewSection`. Rest intervals set `restChip`
/// instead of a numbered `title`/`detail` pair — the sheet renders those as
/// small chips (`REST 60S` / `REST · YOU END IT`), never as monospace text.
struct PreviewStep: Equatable, Identifiable {
    let id = UUID()
    /// 1-based within its section; `0` for rest chips (no numbered badge).
    let number: Int
    let title: String
    let detail: String?
    let restChip: String?

    static func == (lhs: PreviewStep, rhs: PreviewStep) -> Bool {
        lhs.number == rhs.number
            && lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.restChip == rhs.restChip
    }
}

/// A banded group of steps for the preview sheet (warm-up, a repeat set, cool-down, …).
struct PreviewSection: Equatable, Identifiable {
    let id = UUID()
    let kind: PreviewBandKind
    /// Display label for the band, e.g. "WARM-UP" — mirrors `kind.label`.
    var band: String { kind.label }
    /// Repeat count badge, e.g. "×3". `nil` for warm-up/cool-down/ungrouped work.
    let tag: String?
    let steps: [PreviewStep]

    static func == (lhs: PreviewSection, rhs: PreviewSection) -> Bool {
        lhs.kind == rhs.kind && lhs.tag == rhs.tag && lhs.steps == rhs.steps
    }
}

/// Short SPORT token for the preview header's mono meta line
/// (`NATIVE WORKOUT APP · {SPORT} · {N} STEPS`). Parses `sportType` directly
/// from the mapper JSON since `WKPlanDTO.sportType` isn't a public property.
enum WorkoutKitSportLabel {
    private struct Payload: Decodable { let sportType: String? }

    private static let knownLabels: [String: String] = [
        "traditionalStrengthTraining": "STRENGTH",
        "functionalStrengthTraining": "STRENGTH",
        "strengthTraining": "STRENGTH",
        "highIntensityIntervalTraining": "HIIT",
        "running": "RUN",
        "cycling": "BIKE",
        "swimming": "SWIM",
        "walking": "WALK",
        "coreTraining": "CORE",
        "yoga": "YOGA",
        "other": "WORKOUT"
    ]

    static func label(from planJSON: Data) -> String {
        guard
            let payload = try? JSONDecoder().decode(Payload.self, from: planJSON),
            let raw = payload.sportType,
            !raw.isEmpty
        else {
            return "WORKOUT"
        }
        return knownLabels[raw] ?? spacedUppercase(raw)
    }

    private static func spacedUppercase(_ raw: String) -> String {
        var result = ""
        for (index, character) in raw.enumerated() {
            if character.isUppercase, index != 0 {
                result.append(" ")
            }
            result.append(character)
        }
        return result.uppercased()
    }
}

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

    /// Banded preview sections for the Apple Watch preview sheet (AMA-2371).
    /// Warm-up / cool-down each get their own single-step band; repeat sets
    /// get a "WORK ×N" band with rest children demoted to chips; consecutive
    /// standalone work steps are grouped into a single "WORK" band.
    static func sections(from planJSON: Data) -> [PreviewSection] {
        guard let dto = try? WorkoutKitSync.default.parse(from: planJSON) else { return [] }
        var out: [PreviewSection] = []
        var pendingSteps: [WKPlanDTO.Interval.Step] = []

        func flushPendingWork() {
            guard !pendingSteps.isEmpty else { return }
            out.append(PreviewSection(kind: .work, tag: nil, steps: previewSteps(for: pendingSteps)))
            pendingSteps = []
        }

        for interval in dto.intervals {
            switch interval {
            case .warmup(let seconds, _):
                flushPendingWork()
                out.append(PreviewSection(
                    kind: .warmup,
                    tag: nil,
                    steps: [PreviewStep(number: 1, title: "Warm-up", detail: durationLabel(seconds), restChip: nil)]
                ))
            case .cooldown(let seconds, _):
                flushPendingWork()
                out.append(PreviewSection(
                    kind: .cooldown,
                    tag: nil,
                    steps: [PreviewStep(number: 1, title: "Cool-down", detail: durationLabel(seconds), restChip: nil)]
                ))
            case .repeatSet(let reps, let steps):
                flushPendingWork()
                out.append(PreviewSection(kind: .work, tag: "×\(reps)", steps: previewSteps(for: steps)))
            case .step(let step):
                pendingSteps.append(step)
            }
        }
        flushPendingWork()
        return out
    }

    /// Converts a flat run of DTO steps into numbered work rows / rest chips,
    /// renumbering so rest children don't consume a number badge.
    private static func previewSteps(for steps: [WKPlanDTO.Interval.Step]) -> [PreviewStep] {
        var out: [PreviewStep] = []
        var number = 1
        for step in steps {
            if isRest(step) {
                out.append(PreviewStep(number: 0, title: "", detail: nil, restChip: restChip(for: step)))
            } else {
                out.append(PreviewStep(number: number, title: workTitle(for: step), detail: workDetail(for: step), restChip: nil))
                number += 1
            }
        }
        return out
    }

    private static func isRest(_ step: WKPlanDTO.Interval.Step) -> Bool {
        let kind = step.kind.lowercased()
        return kind == "rest" || kind == "recovery"
    }

    /// `REST 60S` for timed rest, `REST · YOU END IT` for open/tap-to-end rest.
    private static func restChip(for step: WKPlanDTO.Interval.Step) -> String {
        if let seconds = step.seconds, seconds > 0 {
            return "REST \(seconds)S"
        }
        return "REST · YOU END IT"
    }

    private static func workTitle(for step: WKPlanDTO.Interval.Step) -> String {
        let name = step.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return step.kind.isEmpty ? "Step" : step.kind.capitalized
    }

    private static func workDetail(for step: WKPlanDTO.Interval.Step) -> String? {
        if let reps = step.reps { return "\(reps) reps" }
        if let seconds = step.seconds { return durationLabel(seconds) }
        return nil
    }

    private static func durationLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) min"
        }
        return "\(seconds)s"
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
