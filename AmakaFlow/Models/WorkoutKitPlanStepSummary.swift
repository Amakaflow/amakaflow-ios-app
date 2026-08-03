//
//  WorkoutKitPlanStepSummary.swift
//  AmakaFlow
//
//  AMA-2360 — human-readable step lines from mapper WKPlanDTO for Apple preview.
//  AMA-2371 — banded `sections(from:)` for the Runna-style Apple Watch preview
//  sheet; rest becomes a chip instead of a monospace dump line.
//  AMA-2374 — exercise-named bands (Mobility prep / Barbell back squat · N SETS)
//  matching `SDWatchSteps` in the send-flow redesign, not WARM-UP/WORK labels.
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

    static func == (lhs: PreviewStep, rhs: PreviewStep) -> Bool {
        lhs.number == rhs.number
            && lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.restChip == rhs.restChip
    }
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

    /// AMA-2371 compatibility — older call sites keyed off `kind`.
    var kind: PreviewBandAccent { accent }

    static func == (lhs: PreviewSection, rhs: PreviewSection) -> Bool {
        lhs.accent == rhs.accent
            && lhs.band == rhs.band
            && lhs.tag == rhs.tag
            && lhs.steps == rhs.steps
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

    // MARK: - Runna exercise-named sections (AMA-2374)

    /// Banded preview sections matching `SDWatchSteps`: Mobility prep / exercise · N SETS.
    /// Rest chips attach to the preceding work row (right side), never as dump lines.
    static func sections(from planJSON: Data) -> [PreviewSection] {
        guard let dto = try? WorkoutKitSync.default.parse(from: planJSON) else { return [] }
        let atoms = flatten(intervals: dto.intervals)
        return buildSections(from: atoms)
    }

    private enum Atom {
        case mobility(title: String, detail: String?)
        case warmupSet(exercise: String, detail: String?)
        case work(exercise: String, detail: String?, repeatCount: Int)
        case rest(chip: String)
        case cooldown(detail: String)
    }

    private struct PreviewRow {
        let title: String
        let detail: String?
        var rest: String?
        let setCount: Int

        init(title: String, detail: String?, rest: String? = nil, setCount: Int = 1) {
            self.title = title
            self.detail = detail
            self.rest = rest
            self.setCount = setCount
        }
    }

    /// Shared warm-up prefixes (lowercase). Detection and stripping must agree.
    private static let warmupPrefixes = [
        "wu ·", "wu -", "wu –", "wu —", "wu·", "wu–", "wu—", "wu ",
        "warm-up ·", "warm-up -", "warm up ·", "warm-up", "warmup"
    ]

    private static func flatten(intervals: [WKPlanDTO.Interval]) -> [Atom] {
        var out: [Atom] = []
        for interval in intervals {
            switch interval {
            case .warmup(let seconds, _):
                out.append(.mobility(title: "Warm-up", detail: durationLabel(seconds)))
            case .cooldown(let seconds, _):
                out.append(.cooldown(detail: durationLabel(seconds)))
            case .repeatSet(let reps, let steps):
                out.append(contentsOf: flattenRepeat(reps: max(reps, 1), steps: steps))
            case .step(let step):
                out.append(contentsOf: flattenStep(step, repeatCount: 1))
            }
        }
        return out
    }

    private static func flattenRepeat(reps: Int, steps: [WKPlanDTO.Interval.Step]) -> [Atom] {
        var out: [Atom] = []
        let workSteps = steps.filter { !isRest($0) }
        let restSteps = steps.filter { isRest($0) }
        let sharedRestChip = restSteps.first.map { restChipLabel(for: $0) }

        if workSteps.count == 1, let only = workSteps.first {
            return flattenSingleRepeatWork(
                only,
                reps: reps,
                sharedRestChip: sharedRestChip
            )
        }

        // Multi-step repeats: expand one cycle's labels, then attach ×reps on work rows.
        for step in steps {
            if isRest(step) {
                out.append(.rest(chip: restChipLabel(for: step)))
                continue
            }
            out.append(contentsOf: flattenStep(step, repeatCount: reps))
        }
        return out
    }

    private static func flattenSingleRepeatWork(
        _ only: WKPlanDTO.Interval.Step,
        reps: Int,
        sharedRestChip: String?
    ) -> [Atom] {
        let name = displayName(for: only)
        let exercise = exerciseFamily(from: name)
        var out: [Atom] = []
        if isWarmupSetName(name) {
            for _ in 0..<reps {
                out.append(.warmupSet(exercise: exercise, detail: workDetail(for: only)))
                if let sharedRestChip { out.append(.rest(chip: sharedRestChip)) }
            }
        } else if isMobilityName(name) {
            out.append(.mobility(title: name, detail: workDetail(for: only)))
            if let sharedRestChip { out.append(.rest(chip: sharedRestChip)) }
        } else {
            out.append(.work(exercise: exercise, detail: workDetail(for: only), repeatCount: reps))
            if let sharedRestChip { out.append(.rest(chip: sharedRestChip)) }
        }
        return out
    }

    private static func flattenStep(_ step: WKPlanDTO.Interval.Step, repeatCount: Int) -> [Atom] {
        if isRest(step) {
            return [.rest(chip: restChipLabel(for: step))]
        }
        let name = displayName(for: step)
        let exercise = exerciseFamily(from: name)
        if isWarmupSetName(name) {
            return [.warmupSet(exercise: exercise, detail: workDetail(for: step))]
        }
        if isMobilityName(name) {
            return [.mobility(title: name, detail: workDetail(for: step))]
        }
        return [.work(exercise: exercise, detail: workDetail(for: step), repeatCount: max(repeatCount, 1))]
    }

    private static func buildSections(from atoms: [Atom]) -> [PreviewSection] {
        var sections: [PreviewSection] = []
        var number = 1
        var pendingRest: String?
        var mobilityRows: [PreviewRow] = []
        var exerciseName: String?
        var exerciseRows: [PreviewRow] = []

        func makeSteps(from rows: [PreviewRow]) -> [PreviewStep] {
            rows.map { row in
                defer { number += 1 }
                return PreviewStep(
                    number: number,
                    title: row.title,
                    detail: uppercaseDetail(row.detail),
                    restChip: row.rest
                )
            }
        }

        func flushMobility() {
            guard !mobilityRows.isEmpty else { return }
            attachRest(&mobilityRows, pending: &pendingRest)
            let rows = mobilityRows
            mobilityRows = []
            sections.append(PreviewSection(
                accent: .mobility,
                band: "Mobility prep",
                tag: mobilityDurationTag(from: rows.map(\.detail)),
                steps: makeSteps(from: rows)
            ))
        }

        func flushExercise() {
            guard let name = exerciseName, !exerciseRows.isEmpty else {
                exerciseName = nil
                exerciseRows = []
                return
            }
            attachRest(&exerciseRows, pending: &pendingRest)
            let rows = exerciseRows
            let setCount = rows.reduce(0) { $0 + $1.setCount }
            exerciseName = nil
            exerciseRows = []
            sections.append(PreviewSection(
                accent: .work,
                band: name,
                tag: "\(setCount) SETS",
                steps: makeSteps(from: rows)
            ))
        }

        func beginExercise(_ exercise: String) {
            flushMobility()
            if exerciseName != exercise {
                flushExercise()
                exerciseName = exercise
            }
            attachRest(&exerciseRows, pending: &pendingRest)
        }

        for atom in atoms {
            switch atom {
            case .mobility(let title, let detail):
                flushExercise()
                attachRest(&mobilityRows, pending: &pendingRest)
                mobilityRows.append(PreviewRow(title: title, detail: detail))

            case .warmupSet(let exercise, let detail):
                beginExercise(exercise)
                exerciseRows.append(PreviewRow(title: "Warm-up set", detail: detail, setCount: 1))

            case .work(let exercise, let detail, let repeatCount):
                beginExercise(exercise)
                let title = repeatCount > 1 ? "Working sets ×\(repeatCount)" : "Working set"
                exerciseRows.append(PreviewRow(title: title, detail: detail, setCount: max(repeatCount, 1)))

            case .rest(let chip):
                pendingRest = chip

            case .cooldown(let detail):
                flushMobility()
                flushExercise()
                pendingRest = nil
                sections.append(PreviewSection(
                    accent: .cooldown,
                    band: "Cool-down",
                    tag: nil,
                    steps: [PreviewStep(
                        number: number,
                        title: "Cool-down",
                        detail: uppercaseDetail(detail),
                        restChip: nil
                    )]
                ))
                number += 1
            }
        }

        flushMobility()
        flushExercise()
        // Trailing rest with no prior work is dropped (nothing to pin the chip to).
        return sections
    }

    private static func attachRest(_ rows: inout [PreviewRow], pending: inout String?) {
        defer { pending = nil }
        guard let pending, !rows.isEmpty else { return }
        rows[rows.count - 1].rest = pending
    }

    private static func mobilityDurationTag(from details: [String?]) -> String? {
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

    private static func parseMinutes(_ detail: String) -> Int? {
        let lower = detail.lowercased()
        guard lower.contains("min") else { return nil }
        let digits = lower.prefix(while: { $0.isNumber || $0 == " " }).filter(\.isNumber)
        return Int(String(digits))
    }

    /// Accept only `durationLabel` seconds form (`"120s"`), never `"10 reps"`.
    private static func parseSeconds(_ detail: String) -> Int? {
        let lower = detail.lowercased()
        guard lower.hasSuffix("s") else { return nil }
        let digits = String(lower.dropLast())
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    private static func uppercaseDetail(_ detail: String?) -> String? {
        guard let detail, !detail.isEmpty else { return nil }
        return detail.uppercased()
    }

    private static func displayName(for step: WKPlanDTO.Interval.Step) -> String {
        let name = step.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return step.kind.isEmpty ? "Step" : step.kind.capitalized
    }

    /// Strip warm-up prefixes so "WU · Barbell back squat" groups under the exercise band.
    private static func exerciseFamily(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard let prefix = warmupPrefixes.first(where: { lower.hasPrefix($0) }) else {
            return trimmed
        }
        let stripped = String(trimmed.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? name : stripped
    }

    private static func isWarmupSetName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return warmupPrefixes.contains { lower.hasPrefix($0) }
    }

    private static func isMobilityName(_ name: String) -> Bool {
        let lower = name.lowercased()
        let tokens = [
            "jump rope", "jumprope", "mobility", "foam roll", "foam roller",
            "world's greatest", "openers", "dynamic stretch", "band pull"
        ]
        return tokens.contains { lower.contains($0) }
    }

    private static func isRest(_ step: WKPlanDTO.Interval.Step) -> Bool {
        let kind = step.kind.lowercased()
        return kind == "rest" || kind == "recovery"
    }

    /// `REST 60S` for timed rest, `REST · YOU END IT` for open/tap-to-end rest.
    private static func restChipLabel(for step: WKPlanDTO.Interval.Step) -> String {
        if let seconds = step.seconds, seconds > 0 {
            return "REST \(seconds)S"
        }
        return "REST · YOU END IT"
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
        if isRest(step) {
            if let seconds = step.seconds {
                return "Rest · \(seconds)s"
            }
            return "Rest · tap"
        }
        let kind = step.kind.lowercased()
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
