//
//  WorkoutBandGrouping.swift
//  AmakaFlow
//
//  AMA-2395 — semantic band sections, replacing "Block 7" / "Round 1–3" and
//  the duplicated "WU · squat" rows.
//
//  Pure display-layer grouping: it never mutates stored blocks. Both the saved
//  detail and the pre-save preview render from this, so an imported workout
//  looks the same before and after it is saved.
//
//  Naming contract: the literal string "Block N" must never render. Sections
//  are named for what they ARE — the structure (`CIRCUIT · 8 ROUNDS`), the main
//  lift (`SQUAT · 3 ROUNDS`), or the dominant modality (`CONDITIONING`).
//

import Foundation

// MARK: - Model

/// Drives the 3px left band colour. Colours live in the view layer.
enum WorkoutBandKind: String {
    case warmUp
    /// Strength work — lime.
    case work
    /// Cardio / conditioning / core — blue.
    case conditioning
    case cooldown
}

struct WorkoutBandRow: Identifiable, Equatable {
    let id: String
    let name: String
    let modality: WorkoutModality
    /// One grammar: `3 × 8`, `3 × 8–12`, `500 M`, `1.0 KM`, `3:00`, `12 CAL`, `OPEN`,
    /// with `· REST 90S` / `· ≈ 7 MIN` suffixes.
    let prescription: String
    /// Folded warm-up ramp detail, e.g. `8 · 5 · BUILDING`.
    let subline: String?
    /// Exercises this row stands for — one, or several when ramps are folded.
    let exerciseIDs: [String]
    /// The exercise to open in the info sheet (the working set, not a ramp).
    let exercise: Exercise?

    static func == (lhs: WorkoutBandRow, rhs: WorkoutBandRow) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.modality == rhs.modality
            && lhs.prescription == rhs.prescription
            && lhs.subline == rhs.subline
            && lhs.exerciseIDs == rhs.exerciseIDs
    }
}

struct WorkoutBand: Identifiable, Equatable {
    let id: String
    /// Already uppercased for the mono band header.
    let title: String
    let kind: WorkoutBandKind
    let rows: [WorkoutBandRow]
    /// Right-aligned subtotal, e.g. `≈ 14 MIN` or `96 MIN`.
    let timeLabel: String
    let seconds: Int
    let isEstimate: Bool

    static func == (lhs: WorkoutBand, rhs: WorkoutBand) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.kind == rhs.kind
            && lhs.rows == rhs.rows && lhs.seconds == rhs.seconds
    }
}

// MARK: - Grouping

enum WorkoutBandGrouping {

    static func bands(
        for workout: Workout,
        estimate: WorkoutDurationEstimate? = nil
    ) -> [WorkoutBand] {
        let resolved = estimate ?? WorkoutDurationEstimator.estimate(for: workout)
        return bands(blocks: workout.blocks, estimate: resolved)
    }

    static func bands(blocks rawBlocks: [Block], estimate: WorkoutDurationEstimate) -> [WorkoutBand] {
        let blocks = rawBlocks.filter { !$0.exercises.isEmpty }
        guard !blocks.isEmpty else { return [] }

        // 1 — pull every warm-up ramp entry out, wherever it was hiding. They
        //     never get their own block and never render as duplicate rows.
        var rampExercises: [Exercise] = []
        var workingBlocks: [(block: Block, exercises: [Exercise])] = []
        for block in blocks {
            let ramps = block.exercises.filter(isWarmupRamp)
            rampExercises.append(contentsOf: ramps)
            workingBlocks.append((block, block.exercises.filter { !isWarmupRamp($0) }))
        }

        // 2 — classify each block, then merge runs of plain unlabeled singles so
        //     a legacy "one block per exercise" import isn't a wall of bands.
        let groups = mergeLooseStraightBlocks(classify(workingBlocks))

        // 3 — build the bands, folding ramps into WARM-UP.
        var bands: [PartialBand] = []
        var warmUpRows = rampRows(from: rampExercises)

        for group in groups where !group.exercises.isEmpty || group.role == .warmUp {
            let rows = group.exercises.map { row(for: $0, estimate: estimate) }
            if group.role == .warmUp {
                warmUpRows = rows + warmUpRows
                bands.append(
                    PartialBand(
                        id: group.id,
                        title: "WARM-UP",
                        kind: .warmUp,
                        rows: [],
                        blockIDs: group.blockIDs,
                        isWarmUpSink: true
                    )
                )
            } else {
                bands.append(
                    PartialBand(
                        id: group.id,
                        title: title(for: group),
                        kind: kind(for: group),
                        rows: rows,
                        blockIDs: group.blockIDs,
                        isWarmUpSink: false
                    )
                )
            }
        }

        // Ramps with no warm-up block to live in still never render loose.
        if !warmUpRows.isEmpty, !bands.contains(where: { $0.isWarmUpSink }) {
            bands.insert(
                PartialBand(
                    id: "band-warmup",
                    title: "WARM-UP",
                    kind: .warmUp,
                    rows: [],
                    blockIDs: [],
                    isWarmUpSink: true
                ),
                at: 0
            )
        }
        if let sinkIndex = bands.firstIndex(where: { $0.isWarmUpSink }) {
            bands[sinkIndex].rows = warmUpRows
        }

        return finalise(bands.filter { !$0.rows.isEmpty }, estimate: estimate, blocks: blocks)
    }

    // MARK: - Rows

    private static func row(for exercise: Exercise, estimate: WorkoutDurationEstimate) -> WorkoutBandRow {
        WorkoutBandRow(
            id: exercise.id,
            name: exercise.name,
            modality: WorkoutSportHonesty.modality(for: exercise),
            prescription: WorkoutBandPrescription.line(
                for: exercise,
                estimate: estimate.seconds(forExerciseID: exercise.id)
            ),
            subline: nil,
            exerciseIDs: [exercise.id],
            exercise: exercise
        )
    }

    /// Collapse every `WU · squat 8` / `WU · squat 5` entry for one movement into
    /// a single ramp row: `Squat — warm-up ramp` / `8 · 5 · BUILDING`.
    private static func rampRows(from ramps: [Exercise]) -> [WorkoutBandRow] {
        guard !ramps.isEmpty else { return [] }
        var order: [String] = []
        var grouped: [String: [Exercise]] = [:]
        for ramp in ramps {
            let key = baseName(of: ramp.name).lowercased()
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(ramp)
        }

        return order.compactMap { key in
            guard let entries = grouped[key], let first = entries.first else { return nil }
            let display = baseName(of: first.name)
            let steps = entries.compactMap { rampStepLabel(for: $0) }
            var parts = steps
            if steps.count > 1 { parts.append("BUILDING") }
            return WorkoutBandRow(
                id: "ramp-\(key)",
                name: "\(display) — warm-up ramp",
                modality: WorkoutSportHonesty.modality(for: first),
                prescription: parts.joined(separator: " · "),
                subline: nil,
                exerciseIDs: entries.map(\.id),
                exercise: first
            )
        }
    }

    private static func rampStepLabel(for exercise: Exercise) -> String? {
        if let reps = exercise.reps?.trimmingCharacters(in: .whitespacesAndNewlines), !reps.isEmpty {
            return reps.uppercased()
        }
        if let seconds = exercise.durationSeconds, seconds > 0 {
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        if let metres = exercise.distance, metres > 0 {
            return WorkoutBandPrescription.distanceLabel(metres: metres)
        }
        return nil
    }

    /// `WU · squat`, `WU: Squat`, `WU squat` → `Squat`.
    static func baseName(of raw: String) -> String {
        let stripped = raw.replacingOccurrences(
            of: #"^\s*(wu|warm[\s-]?up)\b[\s:·\-–]*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? raw : trimmed
        // "squat" → "Squat"; leave already-capitalised names alone.
        guard let first = name.first, first.isLowercase else { return name }
        return first.uppercased() + name.dropFirst()
    }

    static func isWarmupRamp(_ exercise: Exercise) -> Bool {
        exercise.name.range(
            of: #"^\s*(wu|warm[\s-]?up)\b[\s:·\-–]"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    // MARK: - Classification

    private enum BandRole {
        case warmUp
        case cooldown
        case main
    }

    private struct BlockGroup {
        var id: String
        var role: BandRole
        var blocks: [Block]
        var exercises: [Exercise]
        var blockIDs: [String] { blocks.map(\.id) }
        var primary: Block? { blocks.first }
        /// True when several unlabeled blocks were merged into one band.
        var isMerged: Bool { blocks.count > 1 }
    }

    private static func classify(_ input: [(block: Block, exercises: [Exercise])]) -> [BlockGroup] {
        input.enumerated().map { index, entry in
            BlockGroup(
                id: entry.block.id,
                role: role(for: entry.block, exercises: entry.exercises, index: index, all: input),
                blocks: [entry.block],
                exercises: entry.exercises
            )
        }
    }

    private static func role(
        for block: Block,
        exercises: [Exercise],
        index: Int,
        all: [(block: Block, exercises: [Exercise])]
    ) -> BandRole {
        let label = (block.label ?? "").lowercased()
        if label.contains("warm") || label.contains("primer") { return .warmUp }
        if label.contains("cool") { return .cooldown }

        // An unlabeled short opener with no loaded work is a warm-up, whatever
        // the exporter called it — that's what makes a 3:00 jump-rope block
        // read as WARM-UP instead of its own nameless section.
        if index == 0, all.count > 1, isGenericLabel(block.label), isShortOpener(exercises) {
            return .warmUp
        }
        return .main
    }

    private static func isShortOpener(_ exercises: [Exercise]) -> Bool {
        guard !exercises.isEmpty else { return false }
        let hasLoadedWork = exercises.contains { exercise in
            WorkoutSportHonesty.modality(for: exercise) == .lift || exercise.load != nil
        }
        guard !hasLoadedWork else { return false }
        let seconds = exercises.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        return seconds > 0 && seconds <= 6 * 60
    }

    /// Consecutive plain single-round unlabeled blocks are one band, not N.
    private static func mergeLooseStraightBlocks(_ groups: [BlockGroup]) -> [BlockGroup] {
        var result: [BlockGroup] = []
        for group in groups {
            guard let block = group.primary else { continue }
            let isLoose = group.role == .main
                && block.structure == .straight
                && max(1, block.rounds) == 1
                && isGenericLabel(block.label)
            if isLoose,
               var previous = result.last,
               previous.role == .main,
               let previousBlock = previous.primary,
               previousBlock.structure == .straight,
               max(1, previousBlock.rounds) == 1,
               isGenericLabel(previousBlock.label) {
                previous.blocks.append(block)
                previous.exercises.append(contentsOf: group.exercises)
                result[result.count - 1] = previous
            } else {
                result.append(group)
            }
        }
        return result
    }

    static func isGenericLabel(_ label: String?) -> Bool {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return true
        }
        return label.range(
            of: #"^(main( block)?|block\s*\d*|section\s*\d*|round\s*\d*([–-]\d+)?|amrap|exercises?)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    // MARK: - Titles

    private static func title(for group: BlockGroup) -> String {
        guard let block = group.primary else { return "WORK" }
        if group.role == .cooldown { return "COOLDOWN" }

        let rounds = max(1, block.rounds)
        let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Named structures keep their name AND their shape.
        switch block.structure {
        case .emom:
            return "EMOM \(rounds)"
        case .amrap:
            return "AMRAP \(rounds)"
        case .tabata:
            return roundsSuffixed("TABATA", rounds: rounds)
        case .circuit, .timedCircuit:
            var title = roundsSuffixed("CIRCUIT", rounds: rounds)
            if rotatesWithoutRest(block) { title += " · ROTATE, NO REST" }
            return title
        case .superset:
            let lead = leadLiftName(in: group.exercises)
            let shape = "SUPERSET × \(rounds)"
            return lead.map { "\($0.uppercased()) · \(shape)" } ?? shape
        case .straight:
            break
        }

        // "For time" is a named shape even on a straight block.
        if label.range(of: #"for\s*time"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return roundsSuffixed("FOR TIME", rounds: rounds)
        }
        if !isGenericLabel(label), !group.isMerged {
            return roundsSuffixed(label.uppercased(), rounds: rounds)
        }
        // A plain block built around one main lift takes the lift's name.
        if let lift = soleMovementName(in: group.exercises) {
            return roundsSuffixed(lift.uppercased(), rounds: rounds)
        }
        return roundsSuffixed(derivedName(for: group.exercises), rounds: rounds)
    }

    private static func roundsSuffixed(_ title: String, rounds: Int) -> String {
        rounds > 1 ? "\(title) · \(rounds) ROUNDS" : title
    }

    private static func rotatesWithoutRest(_ block: Block) -> Bool {
        block.exercises.count > 1
            && (block.restBetweenSeconds ?? 0) == 0
            && block.exercises.allSatisfy { ($0.restSeconds ?? 0) == 0 }
    }

    /// The one MAIN LIFT a block is built around, if there is exactly one.
    /// Deliberately lift-only: a block of planks is `CORE`, not `PLANK`.
    private static func soleMovementName(in exercises: [Exercise]) -> String? {
        let names = Set(exercises.map { baseName(of: $0.name).lowercased() })
        guard names.count == 1,
              let first = exercises.first,
              WorkoutSportHonesty.modality(for: first) == .lift else {
            return nil
        }
        return baseName(of: first.name)
    }

    private static func leadLiftName(in exercises: [Exercise]) -> String? {
        let lift = exercises.first { WorkoutSportHonesty.modality(for: $0) == .lift }
        return (lift ?? exercises.first).map { baseName(of: $0.name) }
    }

    /// Untitled mixed blocks are named for what they mostly are.
    private static func derivedName(for exercises: [Exercise]) -> String {
        switch WorkoutSportHonesty.dominantModality(of: exercises) {
        case .cardioMachine, .run: return "CONDITIONING"
        case .bodyweight: return "CORE"
        case .lift, .unknown: return "ACCESSORIES"
        }
    }

    private static func kind(for group: BlockGroup) -> WorkoutBandKind {
        switch group.role {
        case .warmUp: return .warmUp
        case .cooldown: return .cooldown
        case .main:
            switch WorkoutSportHonesty.dominantModality(of: group.exercises) {
            case .cardioMachine, .run, .bodyweight: return .conditioning
            case .lift, .unknown: return .work
            }
        }
    }

    // MARK: - Subtotals

    private struct PartialBand {
        let id: String
        let title: String
        let kind: WorkoutBandKind
        var rows: [WorkoutBandRow]
        let blockIDs: [String]
        let isWarmUpSink: Bool
    }

    /// Band seconds = its rows' seconds + the overhead (rest between rounds,
    /// transition padding) of the blocks it owns, so the bands still sum to the
    /// workout total even though ramps moved between them.
    private static func finalise(
        _ partials: [PartialBand],
        estimate: WorkoutDurationEstimate,
        blocks: [Block]
    ) -> [WorkoutBand] {
        let overheads = blockOverheads(estimate: estimate, blocks: blocks)
        // Each block's overhead is claimed exactly once, by the band holding
        // most of its exercises — otherwise the subtotals wouldn't add up.
        var claimed: Set<String> = []

        return partials.map { partial in
            let exerciseIDs = partial.rows.flatMap(\.exerciseIDs)
            var component = estimate.component(forExerciseIDs: exerciseIDs)
            var seconds = component.seconds
            var isEstimate = component.isEstimate

            for blockID in owningBlockIDs(for: exerciseIDs, blocks: blocks) where !claimed.contains(blockID) {
                claimed.insert(blockID)
                seconds += overheads[blockID] ?? 0
                if estimate.seconds(forBlockID: blockID)?.isEstimate == true { isEstimate = true }
            }
            component = WorkoutDurationComponent(id: partial.id, seconds: seconds, isEstimate: isEstimate)

            return WorkoutBand(
                id: partial.id,
                title: partial.title,
                kind: partial.kind,
                rows: partial.rows,
                timeLabel: component.label,
                seconds: seconds,
                isEstimate: isEstimate
            )
        }
    }

    private static func blockOverheads(
        estimate: WorkoutDurationEstimate,
        blocks: [Block]
    ) -> [String: Int] {
        var overheads: [String: Int] = [:]
        for block in blocks {
            let blockSeconds = estimate.seconds(forBlockID: block.id)?.seconds ?? 0
            let exerciseSeconds = block.exercises.reduce(0) {
                $0 + (estimate.seconds(forExerciseID: $1.id)?.seconds ?? 0)
            }
            overheads[block.id] = max(0, blockSeconds - exerciseSeconds)
        }
        return overheads
    }

    /// Blocks where this band holds a strict majority of the exercises.
    private static func owningBlockIDs(for exerciseIDs: [String], blocks: [Block]) -> [String] {
        let held = Set(exerciseIDs)
        return blocks.compactMap { block in
            guard !block.exercises.isEmpty else { return nil }
            let mine = block.exercises.filter { held.contains($0.id) }.count
            return mine * 2 > block.exercises.count ? block.id : nil
        }
    }
}

// MARK: - One prescription grammar

enum WorkoutBandPrescription {
    /// `3 × 8` · `3 × 8–12` · `500 M` · `1.0 KM` · `3:00` · `12 CAL` · `OPEN`,
    /// plus `· REST 90S` and `· ≈ 7 MIN` suffixes. One format everywhere.
    static func line(for exercise: Exercise, estimate: WorkoutDurationComponent?) -> String {
        var parts: [String] = []
        let primary = PrescriptionFormatter.primaryLine(
            PrescriptionFormatter.effective(from: exercise).primary
        )
        parts.append((primary?.isEmpty == false ? primary! : "OPEN").uppercased())

        if let rest = exercise.restSeconds, rest > 0 {
            parts.append("REST \(rest)S")
        }
        // Per-exercise minutes only earn their place on estimated (strength)
        // rows — a timed row already shows its own duration.
        if let estimate, estimate.isEstimate, estimate.seconds >= 60, exercise.durationSeconds == nil {
            parts.append(WorkoutDurationEstimate.label(seconds: estimate.seconds, isEstimate: true))
        }
        return parts.joined(separator: " · ")
    }

    static func distanceLabel(metres: Double) -> String {
        metres >= 1000
            ? String(format: "%.1f KM", metres / 1000)
            : "\(Int(metres.rounded())) M"
    }
}
