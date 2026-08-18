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

/// One row of a Circuit band, with the recovery chip that follows it.
struct CircuitStation {
    let exercise: String
    let detail: String?
    var restChip: String?

    init(exercise: String, detail: String?, restChip: String? = nil) {
        self.exercise = exercise
        self.detail = detail
        self.restChip = restChip
    }
}

/// Private builder so `WorkoutKitPlanStepSummary` stays under type_body_length.
private enum PreviewSectionBuilder {
    private enum Atom {
        case mobility(title: String, detail: String?)
        case warmupSet(exercise: String, detail: String?)
        case work(exercise: String, detail: String?, repeatCount: Int, timed: Bool)
        /// Multi-station circuit/superset: one band, N rounds, stations listed
        /// once. `restChip` is the recovery that follows *that* station —
        /// AMA-2423 station transitions come one per station, so a single
        /// end-of-round chip would under-report the delivered structure.
        case circuit(reps: Int, stations: [CircuitStation])
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
        let nativeWarmupName = WorkoutKitPlanNativeWarmup.displayName(from: planJSON)
        return buildSections(
            from: flatten(intervals: dto.intervals, nativeWarmupDisplayName: nativeWarmupName)
        )
    }

    private static func flatten(
        intervals: [WKPlanDTO.Interval],
        nativeWarmupDisplayName: String?
    ) -> [Atom] {
        var out: [Atom] = []
        var consumedNativeWarmupName = false
        for interval in intervals {
            switch interval {
            case .warmup(let seconds, _):
                let title = WorkoutKitPlanNativeWarmup.previewTitle(
                    nativeWarmupDisplayName: nativeWarmupDisplayName,
                    consumedNativeWarmupName: &consumedNativeWarmupName
                )
                out.append(.mobility(title: title, detail: durationLabel(seconds)))
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
        let sharedRestChip = steps.first { isRest($0) }.map { restChipLabel(for: $0) }

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
            return flattenStepsInOrder(steps, iterations: 1, repeatCount: reps)
        }

        // Mapper emits per-exercise ramps as one non-repeating block of N warm-up
        // work steps (`IntervalBlockDTO(iterations: 1, steps: wu_steps)`). Treating
        // that as a Circuit orphans the ramps from the working-set band and falsely
        // captions "NO WARM-UPS — YOUR CALL" (AMA-2408 dogfood). Walk the full
        // step list so any between-ramp rests stay pinned in order.
        if workSteps.allSatisfy({ isWarmupSetName(displayName(for: $0)) }) {
            return flattenStepsInOrder(steps, iterations: reps, repeatCount: 1)
        }

        return flattenCircuit(reps: reps, steps: steps, sharedRestChip: sharedRestChip)
    }

    private static func flattenStepsInOrder(
        _ steps: [WKPlanDTO.Interval.Step],
        iterations: Int,
        repeatCount: Int
    ) -> [Atom] {
        var out: [Atom] = []
        for _ in 0..<max(iterations, 1) {
            for step in steps {
                out.append(contentsOf: flattenStep(step, repeatCount: repeatCount))
            }
        }
        return out
    }

    /// Walks in order so each recovery pins to the station it follows. A circuit
    /// with one end-of-round rest still lands that chip on the last station
    /// (unchanged); a per-station transition now shows on each.
    private static func flattenCircuit(
        reps: Int,
        steps: [WKPlanDTO.Interval.Step],
        sharedRestChip: String?
    ) -> [Atom] {
        var stations: [CircuitStation] = []
        var leadingRestChip: String?
        for step in steps {
            guard !isRest(step) else {
                let chip = restChipLabel(for: step)
                if stations.isEmpty {
                    leadingRestChip = leadingRestChip ?? chip
                } else {
                    stations[stations.count - 1].restChip = chip
                }
                continue
            }
            stations.append(
                CircuitStation(exercise: displayName(for: step), detail: workDetail(for: step))
            )
        }
        var out: [Atom] = [.circuit(reps: reps, stations: stations)]
        // Recovery declared before any station has nothing to pin to inside the
        // band; keep the pre-AMA-2423 fallback of trailing it onto the circuit.
        if stations.last?.restChip == nil, let chip = leadingRestChip ?? sharedRestChip {
            out.append(.rest(chip: chip))
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

    /// Strip warm-up prefixes so "WU · Barbell back squat" / "Warm-up · Name"
    /// groups under the exercise band. Also strip trailing detail segments
    /// (` · 11`, ` · LIGHT · ~40%`) so intensity-labeled warm-up steps land
    /// under the same band as the working sets (AMA-2408 dogfood).
    private static func exerciseFamily(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let withoutPrefix: String
        if let prefix = warmupPrefixes.first(where: { lower.hasPrefix($0) }) {
            let stripped = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            withoutPrefix = stripped.isEmpty ? trimmed : stripped
        } else {
            withoutPrefix = trimmed
        }
        return baseExerciseName(from: withoutPrefix)
    }

    /// `"Machine Lateral Raises · LIGHT · ~40%"` / `"Incline Smith · 11"` → base name.
    static func baseExerciseName(from name: String) -> String {
        let parts = name
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return name }
        // Keep leading name tokens until a detail segment (pure digits, or
        // intensity / percent / "LIGHT|MODERATE|HEAVY" note).
        var kept: [String] = []
        for part in parts {
            if isDetailSegment(part) { break }
            kept.append(part)
        }
        return kept.isEmpty ? parts[0] : kept.joined(separator: " · ")
    }

    private static func isDetailSegment(_ part: String) -> Bool {
        if Int(part) != nil { return true }
        let upper = part.uppercased()
        if upper.contains("%") { return true }
        if upper.contains("~") { return true }
        let intensityTokens = ["LIGHT", "MODERATE", "HEAVY", "EASY", "HARD"]
        return intensityTokens.contains { upper == $0 || upper.hasPrefix($0 + " ") }
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

    /// `REST 60S` / `REST · YOU END IT` for plain between-set rest.
    /// AMA-2423: the mapper names station-transition recoveries `"Transition"`
    /// (`_apply_station_transition` → `displayName="Transition"`) — surface
    /// `TRANSITION …` instead so the preview never mislabels it Rest; open
    /// transitions still read as the amber "you end it" chip.
    private static func restChipLabel(for step: WKPlanDTO.Interval.Step) -> String {
        if isTransitionStep(step) {
            if let seconds = step.seconds, seconds > 0 {
                return "TRANSITION \(seconds)S"
            }
            return PreviewStep.openTransitionChip
        }
        if let seconds = step.seconds, seconds > 0 {
            return "REST \(seconds)S"
        }
        return PreviewStep.openRestChip
    }

    private static func isTransitionStep(_ step: WKPlanDTO.Interval.Step) -> Bool {
        guard let name = step.name?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return name.caseInsensitiveCompare("Transition") == .orderedSame
    }

    /// Time-goal work (seconds present, no reps) — EMOM stations, holds, etc.
    private static func isTimedWork(_ step: WKPlanDTO.Interval.Step) -> Bool {
        step.seconds != nil && step.reps == nil
    }

    /// `nil` reps / seconds / meters means no fixed target — an open goal
    /// (AMA-2378 `ActivityGoal.kind == .open` / `RampSet.kind == .open`).
    /// Surfaces as `"Open"` (→ `OPEN` once uppercased) so the preview never
    /// silently drops the row's detail line.
    ///
    /// AMA-2408: when WorkoutKit coerce invents `reps=1` for an intensity-only
    /// warm-up label (`Warm-up · Name · LIGHT · ~40%`), prefer recovering a
    /// trailing digit from the name, else show the intensity note — never lie
    /// with "1 REPS" when the user set 11.
    private static func workDetail(for step: WKPlanDTO.Interval.Step) -> String? {
        if let reps = step.reps {
            if reps == 1, let recovered = repsRecoveredFromWarmupLabel(step.name) {
                return "\(recovered) reps"
            }
            if reps == 1, let note = intensityNoteFromWarmupLabel(step.name) {
                return note
            }
            return "\(reps) reps"
        }
        if let seconds = step.seconds { return durationLabel(seconds) }
        if let meters = step.meters, meters > 0 {
            return WorkoutHelpers.formatDistance(meters: Int(meters.rounded()))
        }
        return "Open"
    }

    /// `"Warm-up · Incline Smith · 11"` → 11. Intensity-only labels → nil.
    static func repsRecoveredFromWarmupLabel(_ name: String?) -> Int? {
        guard let name else { return nil }
        let lower = name.lowercased()
        guard warmupPrefixes.contains(where: { lower.hasPrefix($0) }) else { return nil }
        let parts = name
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let last = parts.last, let value = Int(last), value > 1 else { return nil }
        return value
    }

    /// `"Warm-up · Name · LIGHT · ~40%"` → `"LIGHT · ~40%"`.
    static func intensityNoteFromWarmupLabel(_ name: String?) -> String? {
        guard let name else { return nil }
        let lower = name.lowercased()
        guard let prefix = warmupPrefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        let withoutPrefix = String(name.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = withoutPrefix
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let detail = Array(parts.dropFirst())
        // First intensity/detail segment and everything after — drop name tokens
        // that sit between the exercise name and "LIGHT · ~40%".
        guard let firstDetailIndex = detail.firstIndex(where: isDetailSegment) else {
            return nil
        }
        let note = detail[firstDetailIndex...].joined(separator: " · ")
        return note.isEmpty ? nil : note
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
