//
//  WorkoutKitPlanStepSummary+Sections.swift
//  AmakaFlow
//
//  AMA-2374/2378/2390 — banded Apple Watch preview sections (Mobility /
//  exercise · N SETS / Circuit · N ROUNDS). Split for SwiftLint file_length.
//

import Foundation
import WorkoutKitSync

extension WorkoutKitPlanStepSummary {
    /// Banded preview sections matching `SDWatchSteps`. Rest chips pin to the prior work row.
    static func sections(from planJSON: Data) -> [PreviewSection] {
        PreviewSectionBuilder.sections(from: planJSON)
    }
}

/// Preview content before numbering — shared by flatten + grouping passes.
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

/// Private builder so `WorkoutKitPlanStepSummary` stays under type_body_length.
private enum PreviewSectionBuilder {
    private enum Atom {
        case mobility(title: String, detail: String?)
        case warmupSet(exercise: String, detail: String?)
        case work(exercise: String, detail: String?, repeatCount: Int, timed: Bool)
        /// Multi-station circuit/superset: one band, N rounds, stations listed once.
        case circuit(reps: Int, stations: [(exercise: String, detail: String?)])
        case rest(chip: String)
        case cooldown(detail: String)
    }

    /// Shared warm-up prefixes (lowercase). Detection and stripping must agree.
    private static let warmupPrefixes = [
        "wu ·", "wu -", "wu –", "wu —", "wu·", "wu–", "wu—", "wu ",
        "warm-up ·", "warm-up -", "warm up ·", "warm-up", "warmup"
    ]

    static func sections(from planJSON: Data) -> [PreviewSection] {
        guard let dto = try? WorkoutKitSync.default.parse(from: planJSON) else { return [] }
        return buildSections(from: flatten(intervals: dto.intervals))
    }

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

        // EMOM keeps per-station "Work intervals ×N" bands (mapper names "EMOM · …").
        // Circuit/superset must keep outer iterations as ROUNDS, not fan into SETS.
        if isEmomRepeat(workSteps) {
            var out: [Atom] = []
            for step in steps {
                if isRest(step) {
                    out.append(.rest(chip: restChipLabel(for: step)))
                    continue
                }
                out.append(contentsOf: flattenStep(step, repeatCount: reps))
            }
            return out
        }

        let stations: [(exercise: String, detail: String?)] = workSteps.map { step in
            (displayName(for: step), workDetail(for: step))
        }
        var out: [Atom] = [.circuit(reps: reps, stations: stations)]
        if let sharedRestChip {
            out.append(.rest(chip: sharedRestChip))
        }
        return out
    }

    private static func isEmomRepeat(_ workSteps: [WKPlanDTO.Interval.Step]) -> Bool {
        workSteps.contains { displayName(for: $0).uppercased().contains("EMOM") }
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
            for _ in 0..<reps {
                out.append(.mobility(title: name, detail: workDetail(for: only)))
                if let sharedRestChip { out.append(.rest(chip: sharedRestChip)) }
            }
        } else {
            out.append(.work(
                exercise: exercise,
                detail: workDetail(for: only),
                repeatCount: reps,
                timed: isTimedWork(only)
            ))
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
        return [.work(
            exercise: exercise,
            detail: workDetail(for: step),
            repeatCount: max(repeatCount, 1),
            timed: isTimedWork(step)
        )]
    }

    private static func buildSections(from atoms: [Atom]) -> [PreviewSection] {
        var accumulator = SectionAccumulator()
        for atom in atoms {
            switch atom {
            case .mobility(let title, let detail):
                accumulator.appendMobility(title: title, detail: detail)
            case .warmupSet(let exercise, let detail):
                accumulator.appendWarmupSet(exercise: exercise, detail: detail)
            case .work(let exercise, let detail, let repeatCount, let timed):
                accumulator.appendWork(
                    exercise: exercise,
                    detail: detail,
                    repeatCount: repeatCount,
                    timed: timed
                )
            case .circuit(let reps, let stations):
                accumulator.appendCircuit(reps: reps, stations: stations)
            case .rest(let chip):
                accumulator.setPendingRest(chip)
            case .cooldown(let detail):
                accumulator.appendCooldownAtom(detail: detail)
            }
        }
        return accumulator.finish()
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
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    /// Time-goal work (seconds present, no reps) — EMOM stations, holds, etc.
    private static func isTimedWork(_ step: WKPlanDTO.Interval.Step) -> Bool {
        step.seconds != nil && step.reps == nil
    }

    /// `nil` reps / seconds / meters means no fixed target — an open goal
    /// (AMA-2378 `ActivityGoal.kind == .open` / `RampSet.kind == .open`).
    /// Surfaces as `"Open"` (→ `OPEN` once uppercased) so the preview never
    /// silently drops the row's detail line.
    private static func workDetail(for step: WKPlanDTO.Interval.Step) -> String? {
        if let reps = step.reps { return "\(reps) reps" }
        if let seconds = step.seconds { return durationLabel(seconds) }
        if let meters = step.meters, meters > 0 {
            return WorkoutHelpers.formatDistance(meters: Int(meters.rounded()))
        }
        return "Open"
    }

    /// The legacy singular warmup/cooldown fields encode an open goal as
    /// `seconds: 0` (mapper `legacy_interval_models()`) — a real 0s band
    /// never happens, so 0 unambiguously means open here.
    private static func durationLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Open" }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) min"
        }
        return "\(seconds)s"
    }
}

/// AMA-2378 grouping: soft-activity before first work → mobility; after last
/// work → cooldown. Value type (not MainActor class) for XCTest deinit safety.
private struct SectionAccumulator {
    private var sections: [PreviewSection] = []
    private var number = 1
    private var pendingRest: String?
    private var mobilityRows: [PreviewRow] = []
    private var exerciseName: String?
    private var exerciseRows: [PreviewRow] = []
    private var cooldownRows: [PreviewRow] = []
    private var hasWorked = false

    mutating func setPendingRest(_ chip: String) {
        pendingRest = chip
    }

    mutating func appendMobility(title: String, detail: String?) {
        flushExercise()
        if hasWorked {
            var rows = cooldownRows
            attachPendingRest(to: &rows)
            rows.append(PreviewRow(title: title, detail: detail))
            cooldownRows = rows
        } else {
            var rows = mobilityRows
            attachPendingRest(to: &rows)
            rows.append(PreviewRow(title: title, detail: detail))
            mobilityRows = rows
        }
    }

    mutating func appendWarmupSet(exercise: String, detail: String?) {
        beginExercise(exercise)
        exerciseRows.append(PreviewRow(title: PreviewStep.warmupSetTitle, detail: detail, setCount: 1))
    }

    mutating func appendWork(exercise: String, detail: String?, repeatCount: Int, timed: Bool) {
        beginExercise(exercise)
        let noun = timed ? "Work interval" : "Working set"
        let title = repeatCount > 1 ? "\(noun)s ×\(repeatCount)" : noun
        exerciseRows.append(PreviewRow(title: title, detail: detail, setCount: max(repeatCount, 1)))
    }

    /// Circuit band: stations once, outer iterations as ROUNDS (Library parity).
    mutating func appendCircuit(reps: Int, stations: [(exercise: String, detail: String?)]) {
        flushMobility()
        flushExercise()
        flushCooldownAsInterstitial()
        hasWorked = true
        pendingRest = nil
        let rows = stations.map { PreviewRow(title: $0.exercise, detail: $0.detail, setCount: 1) }
        let tag = reps == 1 ? "1 ROUND" : "\(reps) ROUNDS"
        sections.append(PreviewSection(
            accent: .work,
            band: "Circuit",
            tag: tag,
            steps: makeSteps(from: rows),
            caption: nil
        ))
    }

    /// Legacy single-activity `.cooldown` atom — always merges into
    /// `cooldownRows` alongside any soft-activity rows already pending.
    mutating func appendCooldownAtom(detail: String) {
        flushMobility()
        flushExercise()
        pendingRest = nil
        cooldownRows.append(PreviewRow(title: "Cool-down", detail: detail))
    }

    /// Trailing rest with no prior work is dropped (nothing to pin the chip to).
    mutating func finish() -> [PreviewSection] {
        flushMobility()
        flushExercise()
        flushCooldown()
        return sections
    }

    private mutating func beginExercise(_ exercise: String) {
        flushMobility()
        flushCooldownAsInterstitial()
        hasWorked = true
        if exerciseName != exercise {
            flushExercise()
            exerciseName = exercise
        }
        var rows = exerciseRows
        attachPendingRest(to: &rows)
        exerciseRows = rows
    }

    private mutating func makeSteps(from rows: [PreviewRow]) -> [PreviewStep] {
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

    private mutating func flushMobility() {
        guard !mobilityRows.isEmpty else { return }
        var rows = mobilityRows
        attachPendingRest(to: &rows)
        mobilityRows = []
        sections.append(PreviewSection(
            accent: .mobility,
            band: "Mobility prep",
            tag: bandDurationTag(from: rows.map(\.detail)),
            steps: makeSteps(from: rows)
        ))
    }

    private mutating func flushExercise() {
        guard let name = exerciseName, !exerciseRows.isEmpty else {
            exerciseName = nil
            exerciseRows = []
            return
        }
        var rows = exerciseRows
        attachPendingRest(to: &rows)
        let setCount = rows.reduce(0) { $0 + $1.setCount }
        let hasRamp = rows.contains { $0.title == PreviewStep.warmupSetTitle }
        exerciseName = nil
        exerciseRows = []
        sections.append(PreviewSection(
            accent: .work,
            band: name,
            tag: setCount == 1 ? "1 SET" : "\(setCount) SETS",
            steps: makeSteps(from: rows),
            caption: hasRamp ? nil : WorkoutEnrichmentPushCopy.noWarmupsYourCall
        ))
    }

    /// Flushes rows that looked like a trailing cooldown but turned out to be
    /// a mid-workout break — more work followed, so relabel as an
    /// interstitial mobility band instead of dropping them.
    private mutating func flushCooldownAsInterstitial() {
        guard !cooldownRows.isEmpty else { return }
        var rows = cooldownRows
        attachPendingRest(to: &rows)
        cooldownRows = []
        sections.append(PreviewSection(
            accent: .mobility,
            band: "Mobility prep",
            tag: bandDurationTag(from: rows.map(\.detail)),
            steps: makeSteps(from: rows)
        ))
    }

    /// Real, final cooldown flush — always the last section appended because
    /// it only ever runs at atom-stream end or on the dedicated `.cooldown`
    /// atom (itself guaranteed last by the mapper). Trailing rest after the
    /// cool-down band has nothing to pin to — drop it (AMA-2371 contract).
    private mutating func flushCooldown() {
        guard !cooldownRows.isEmpty else { return }
        pendingRest = nil
        let rows = cooldownRows
        cooldownRows = []
        sections.append(PreviewSection(
            accent: .cooldown,
            band: "Cool-down",
            tag: bandDurationTag(from: rows.map(\.detail)),
            steps: makeSteps(from: rows)
        ))
    }

    /// `rows` must be a local copy — never `&self.mobilityRows` etc.
    private mutating func attachPendingRest(to rows: inout [PreviewRow]) {
        let chip = pendingRest
        pendingRest = nil
        guard let chip, !rows.isEmpty else { return }
        rows[rows.count - 1].rest = chip
    }
}

// MARK: - Shared detail/tag string formatting (file scope, used by both types above)

private func bandDurationTag(from details: [String?]) -> String? {
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

private func uppercaseDetail(_ detail: String?) -> String? {
    guard let detail, !detail.isEmpty else { return nil }
    return detail.uppercased()
}
