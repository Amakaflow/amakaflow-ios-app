//
//  EnrichmentRowSummary.swift
//  AmakaFlow
//
//  AMA-2408 F1 — ONE pure summary home for warm-ups / mobility / cool-down.
//  Grammar: one line, positive assertions only, "SKIPPED" unrepresentable,
//  OFF rows return nil (title + toggle only).
//

import Foundation

enum EnrichmentRowKind: Equatable, Sendable {
    case warmups
    case mobility
    case cooldown
    case rest
}

/// Row summary line for enhance / Watch Item / preview surfaces.
/// Returns `nil` when the row is OFF — callers render title + toggle only.
enum EnrichmentRowSummary {
    /// Amber CTA when warm-ups are ON but nothing is opted in yet.
    static let noRampsYet = "NO RAMPS YET — PICK EXERCISES ›"

    /// Hard cap for a single summary line (ellipsis truncates the tail).
    static let lineHardCap = 52

    // MARK: - Public entry points

    /// Warm-up sets ladder. `nil` when the row is off.
    static func warmups(
        isOn: Bool,
        candidateNames: [String],
        ramps: [PerExerciseRamp]
    ) -> String? {
        guard isOn else { return nil }
        let enabled = enabledRamps(in: ramps, candidates: candidateNames)
        let n = enabled.count
        let m = candidateNames.count
        guard n > 0 else { return noRampsYet }
        guard m > 0 else { return noRampsYet }

        let text: String
        if n == m {
            text = "CUSTOM RAMPS · ALL \(m)"
        } else if n >= 4 {
            text = "CUSTOM RAMPS · \(n) OF \(m)"
        } else if n == 1, let first = enabled.first {
            let name = warmupDisplayName(first.exerciseRef)
            let setCount = max(first.sets.count, 1)
            text = "\(name) · RAMP ×\(setCount) · 1 OF \(m)"
        } else {
            // N = 2…3
            let firstName = warmupDisplayName(enabled[0].exerciseRef)
            let more = n - 1
            text = "\(firstName) + \(more) MORE · \(n) OF \(m)"
        }
        return capped(text, preferringPrefix: true)
    }

    /// Mobility / cool-down sequence ladder. `nil` when the row is off.
    static func sequence(
        isOn: Bool,
        activities: [EnrichmentActivity],
        estimatedMinutes: Int? = nil
    ) -> String? {
        guard isOn else { return nil }
        let n = activities.count
        guard n > 0 else { return nil }

        let text: String
        if n == 1, let only = activities.first {
            let label = WorkoutEnrichmentPushCopy.activitySummaryLabel(
                name: only.name,
                goal: only.goal,
                durationSec: only.durationSec
            )
            text = "\(label) · 1 STEP"
        } else if n <= 3 {
            let tokens = activities.map { sequenceShortToken($0.name) }.joined(separator: " ➜ ")
            text = "\(tokens) · \(n) STEPS"
        } else {
            let minutes = estimatedMinutes
                ?? WorkoutEnrichmentPushCopy.sequenceDurationEstimateMinutes(activities)
            text = "\(n) STEPS · ≈\(minutes) MIN"
        }
        return capped(text, preferringPrefix: true)
    }

    /// Rest row — OFF → nil; ON → live rest detail.
    static func rest(
        isOn: Bool,
        restOpen: Bool,
        restSec: Int,
        target: EnrichmentPushTarget
    ) -> String? {
        guard isOn else { return nil }
        return WorkoutEnrichmentPushCopy.liveRestDetail(
            restOpen: restOpen,
            restSec: restSec,
            target: target
        )
    }

    /// Unified dispatcher used by sheet renderers.
    static func line(
        kind: EnrichmentRowKind,
        isOn: Bool,
        candidateNames: [String] = [],
        ramps: [PerExerciseRamp] = [],
        activities: [EnrichmentActivity] = [],
        restOpen: Bool = false,
        restSec: Int = 60,
        target: EnrichmentPushTarget = .garmin
    ) -> String? {
        switch kind {
        case .warmups:
            return warmups(isOn: isOn, candidateNames: candidateNames, ramps: ramps)
        case .mobility, .cooldown:
            return sequence(isOn: isOn, activities: activities)
        case .rest:
            return rest(isOn: isOn, restOpen: restOpen, restSec: restSec, target: target)
        }
    }

    // MARK: - Display helpers

    /// Uppercased warm-up name with trailing equipment noise dropped so
    /// "Incline Smith Press" → `INCLINE SMITH`.
    static func warmupDisplayName(_ name: String) -> String {
        var words = name
            .uppercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
        let droppable: Set<String> = [
            "PRESS", "MACHINE", "RAISE", "RAISES", "CURL", "EXTENSION", "EXTENSIONS"
        ]
        while words.count > 1, let last = words.last, droppable.contains(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    /// Short token for 2–3 step sequence joins (`SKI ➜ ROPE`).
    static func sequenceShortToken(_ name: String) -> String {
        let words = name
            .uppercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
        guard !words.isEmpty else { return "" }
        if words.count == 1 { return words[0] }
        let last = words[words.count - 1]
        let first = words[0]
        let qualifiers: Set<String> = ["ERG", "MACHINE", "PRESS", "FLOW", "MILL"]
        if qualifiers.contains(last) { return first }
        // Jump Rope → ROPE, Assault Bike → BIKE
        let preferLast: Set<String> = ["ROPE", "BIKE", "ROW", "RUN"]
        if preferLast.contains(last) { return last }
        return first
    }

    static func enabledRamps(
        in ramps: [PerExerciseRamp],
        candidates: [String]
    ) -> [PerExerciseRamp] {
        let candidateKeys = Set(candidates.map(ExerciseKeyNormalizer.normalize))
        return ramps.filter { ramp in
            guard ramp.enabled, !ramp.sets.isEmpty else { return false }
            let key = ExerciseKeyNormalizer.normalize(ramp.exerciseRef)
            return candidateKeys.isEmpty || candidateKeys.contains(key)
        }
    }

    /// Truncate to `lineHardCap` with an ellipsis. Detail (left side of the
    /// ladder) is kept; the exercise name still appears when present.
    static func capped(_ text: String, preferringPrefix: Bool) -> String {
        guard text.count > lineHardCap else { return text }
        let end = text.index(text.startIndex, offsetBy: lineHardCap - 1)
        let head = String(text[..<end]).trimmingCharacters(in: .whitespaces)
        return preferringPrefix ? "\(head)…" : "…\(String(text.suffix(lineHardCap - 1)))"
    }
}
