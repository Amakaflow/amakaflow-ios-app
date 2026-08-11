//
//  WorkoutKitPlanStepSummary+SectionAccumulator.swift
//  AmakaFlow
//
//  AMA-2378/2408 — section grouping accumulator, split from +Sections for
//  SwiftLint file_length.
//

import Foundation

/// Preview content before numbering — shared by flatten + grouping passes.
struct PreviewRow {
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

/// AMA-2378 grouping: soft-activity before first work → mobility; after last
/// work → cooldown. Value type (not MainActor class) for XCTest deinit safety.
struct SectionAccumulator {
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
        // Drop rest that arrived *before* the circuit (nothing earlier to pin to).
        // Rest *after* the circuit is attached in `finish()` via pendingRest.
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

    /// Trailing rest pins to the last work band (circuit rounds / last station).
    /// Rest with no prior work is dropped (nothing to pin the chip to).
    mutating func finish() -> [PreviewSection] {
        flushMobility()
        flushExercise()
        flushCooldown()
        attachTrailingRestToLastWorkSection()
        return sections
    }

    /// Circuit/repeat rest arrives after `appendCircuit` cleared pendingRest —
    /// pin that chip onto the last station so preview matches Apple Workout.
    private mutating func attachTrailingRestToLastWorkSection() {
        guard let chip = pendingRest else { return }
        pendingRest = nil
        guard let index = sections.lastIndex(where: { $0.accent == .work }),
              !sections[index].steps.isEmpty else { return }
        let prior = sections[index]
        var steps = prior.steps
        let last = steps[steps.count - 1]
        steps[steps.count - 1] = PreviewStep(
            number: last.number,
            title: last.title,
            detail: last.detail,
            restChip: chip
        )
        sections[index] = PreviewSection(
            accent: prior.accent,
            band: prior.band,
            tag: prior.tag,
            steps: steps,
            caption: prior.caption
        )
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
