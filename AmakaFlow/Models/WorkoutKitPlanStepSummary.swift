//
//  WorkoutKitPlanStepSummary.swift
//  AmakaFlow
//
//  AMA-2360 — human-readable step lines from mapper WKPlanDTO for Apple preview.
//  AMA-2371 — banded `sections(from:)` for the Runna-style Apple Watch preview
//  sheet; rest becomes a chip instead of a monospace dump line.
//  AMA-2374 — exercise-named bands live in WorkoutKitPlanStepSummary+Sections.swift.
//

import Foundation
import WorkoutKitSync

// MARK: - Section banding (AMA-2371 / AMA-2374)

/// Visual accent for a preview band — drives header tint, not the athlete-facing label.
enum PreviewBandAccent: Equatable {
    case mobility
    case work
    case cooldown
}

/// A single row inside a `PreviewSection`. Rest is attached to the work row as
/// `restChip` (right side), never as its own numbered step.
struct PreviewStep: Equatable, Identifiable {
    let id = UUID()
    /// 1-based across the whole preview (Runna numbering).
    let number: Int
    let title: String
    let detail: String?
    let restChip: String?

    /// Shared title for enrichment-owned warm-up-set rows — keep all
    /// `hasRamp` / `RAMPS` checks on this constant, never a bare literal.
    static let warmupSetTitle = "Warm-up set"

    /// Open/tap-to-end between-set rest chip text (`WorkoutKitPlanStepSummary+Sections.restChipLabel`).
    static let openRestChip = "REST · YOU END IT"
    /// AMA-2423 — open/tap-to-end station-transition chip; same amber "you
    /// end it" feel as `openRestChip`, distinct copy so it never reads as Rest.
    static let openTransitionChip = "TRANSITION · YOU END IT"

    static func == (lhs: PreviewStep, rhs: PreviewStep) -> Bool {
        lhs.number == rhs.number
            && lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.restChip == rhs.restChip
    }

    /// AMA-2378 — no fixed target (reps/time/distance/cals); athlete ends on
    /// tap/Crown. Detail reads the locked `"OPEN"` string set by the section
    /// builder — amber-flag it instead of the usual muted detail styling.
    var isOpenGoal: Bool { detail == "OPEN" }

    /// AMA-2378/2423 — untimed/open rest or station transition between sets
    /// (`"REST · YOU END IT"` / `"TRANSITION · YOU END IT"` chip) — both stay amber.
    var isOpenRest: Bool { restChip == PreviewStep.openRestChip || restChip == PreviewStep.openTransitionChip }
}

/// A banded group of steps for the preview sheet.
/// Band titles are athlete-facing (`Mobility prep`, exercise name) — never
/// `WARM-UP` / `WORK` / `COOL-DOWN`.
struct PreviewSection: Equatable, Identifiable {
    let id = UUID()
    let accent: PreviewBandAccent
    /// Athlete-facing band title, e.g. "Mobility prep" or "Barbell back squat".
    let band: String
    /// Right-side tag, e.g. "~2 MIN" or "5 SETS".
    let tag: String?
    let steps: [PreviewStep]
    /// AMA-2378 — exercise bands with no warm-up-set row surface
    /// `WorkoutEnrichmentPushCopy.noWarmupsYourCall`; `nil` for bands that
    /// don't apply (mobility / cooldown / exercises with a ramp).
    let caption: String?

    init(accent: PreviewBandAccent, band: String, tag: String?, steps: [PreviewStep], caption: String? = nil) {
        self.accent = accent
        self.band = band
        self.tag = tag
        self.steps = steps
        self.caption = caption
    }

    /// AMA-2371 compatibility — older call sites keyed off `kind`.
    var kind: PreviewBandAccent { accent }

    /// True when this work band includes an enrichment warm-up-set row.
    var hasRamp: Bool {
        accent == .work && steps.contains { $0.title == PreviewStep.warmupSetTitle }
    }

    static func == (lhs: PreviewSection, rhs: PreviewSection) -> Bool {
        lhs.accent == rhs.accent
            && lhs.band == rhs.band
            && lhs.tag == rhs.tag
            && lhs.steps == rhs.steps
            && lhs.caption == rhs.caption
    }
}

/// Short SPORT token for the preview header's mono meta line
/// (`NATIVE WORKOUT APP · {SPORT} · {N} STEPS`). Parses `sportType` directly
/// from the mapper JSON since `WKPlanDTO.sportType` isn't a public property.
enum WorkoutKitSportLabel {
    private struct Payload: Decodable {
        let sportType: String?
        let activity: String?
    }

    private static let knownLabels: [String: String] = [
        "traditionalStrengthTraining": "STRENGTH",
        "functionalStrengthTraining": "STRENGTH",
        "strengthTraining": "STRENGTH",
        "highIntensityIntervalTraining": "HIIT",
        "mixedCardio": "MIXED CARDIO",
        "flexibility": "FLEXIBILITY",
        "rowing": "ROWING",
        "elliptical": "ELLIPTICAL",
        "stairClimbing": "STAIR CLIMBING",
        "running": "RUN",
        "cycling": "BIKE",
        "swimming": "SWIM",
        "walking": "WALK",
        "coreTraining": "CORE",
        "yoga": "YOGA",
        "swimBikeRun": "MULTISPORT",
        "other": "WORKOUT"
    ]

    /// Prefer honest `activity` (AMA-2393); fall back to legacy `sportType`.
    static func label(from planJSON: Data) -> String {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: planJSON) else {
            return "WORKOUT"
        }
        if let raw = payload.activity, !raw.isEmpty {
            return knownLabels[raw] ?? spacedUppercase(raw)
        }
        if let raw = payload.sportType, !raw.isEmpty {
            return knownLabels[raw] ?? spacedUppercase(raw)
        }
        return "WORKOUT"
    }

    /// Apple Workout app display name for the `RECORDS AS:` preview line.
    static func recordsAsLabel(from planJSON: Data) -> String {
        label(from: planJSON)
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
        let nativeWarmupName = WorkoutKitPlanNativeWarmup.displayName(from: planJSON)
        var consumedNativeWarmupName = false

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

            let omittedNested = append(
                interval: interval,
                into: &out,
                budget: budget,
                nativeWarmupDisplayName: nativeWarmupName,
                consumedNativeWarmupName: &consumedNativeWarmupName
            )
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
        budget: Int,
        nativeWarmupDisplayName: String?,
        consumedNativeWarmupName: inout Bool
    ) -> Int {
        guard budget > 0 else { return labelCount(for: interval) }
        switch interval {
        case .warmup(let seconds, _):
            let title = WorkoutKitPlanNativeWarmup.previewTitle(
                nativeWarmupDisplayName: nativeWarmupDisplayName,
                consumedNativeWarmupName: &consumedNativeWarmupName
            )
            out.append("\(title) · \(seconds)s")
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

// MARK: - Preview section formatting (shared with +Sections)

func bandDurationTag(from details: [String?]) -> String? {
    var totalSeconds = 0
    var matched = false
    for detail in details {
        guard let detail else { continue }
        if let minutes = parseMinutes(detail) {
            totalSeconds += minutes * 60
            matched = true
        } else if let seconds = parseSeconds(detail) {
            totalSeconds += seconds
            matched = true
        }
    }
    guard matched, totalSeconds > 0 else { return nil }
    let minutes = max(1, Int((Double(totalSeconds) / 60.0).rounded()))
    return "~\(minutes) MIN"
}

private func parseMinutes(_ detail: String) -> Int? {
    let lower = detail.lowercased()
    guard lower.contains("min") else { return nil }
    let digits = lower.prefix(while:) { $0.isNumber || $0 == " " }.filter(\.isNumber)
    return Int(String(digits))
}

/// Accept only `durationLabel` seconds form (`"120s"`), never `"10 reps"`.
private func parseSeconds(_ detail: String) -> Int? {
    let lower = detail.lowercased()
    guard lower.hasSuffix("s") else { return nil }
    let digits = String(lower.dropLast())
    guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
    return Int(digits)
}

func uppercaseDetail(_ detail: String?) -> String? {
    guard let detail, !detail.isEmpty else { return nil }
    return detail.uppercased()
}
