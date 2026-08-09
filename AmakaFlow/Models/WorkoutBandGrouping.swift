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
            && lhs.isEstimate == rhs.isEstimate && lhs.timeLabel == rhs.timeLabel
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
                prescription: parts.isEmpty ? "OPEN" : parts.joined(separator: " · "),
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
}
