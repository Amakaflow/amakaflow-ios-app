//
//  WorkoutBandGrouping.swift
//  AmakaFlow
//
//  AMA-2395 — section styling for the workout detail.
//
//  THE RULE: the stored structure is the truth. One block in, one section out,
//  in source order, with the same exercises in the same order. This file
//  RESTYLES the structure — it never reshapes it. No merging blocks, no
//  promoting a block into a warm-up, no moving rows between sections, no
//  inventing section names.
//
//  Warm-up ramp sets are NOT handled here. They belong to the Apple Watch plan
//  (see WorkoutKitPlanStepSummary+Sections), which is prepared separately from
//  the library workout. The library detail shows the workout as authored.
//
//  Pure display-layer: it never mutates stored blocks.
//

import Foundation

// MARK: - Model

/// Drives the 3px left band colour only. Colours live in the view layer.
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
    /// One grammar: `5 SETS`, `3 × 8`, `3 × 8–12`, `500 M`, `1.0 KM`, `3:00`,
    /// `12 CAL`, `OPEN`, with `· REST 90S` / `· ≈ 7 MIN` suffixes.
    let prescription: String
    let exercise: Exercise?

    static func == (lhs: WorkoutBandRow, rhs: WorkoutBandRow) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.modality == rhs.modality
            && lhs.prescription == rhs.prescription
    }
}

struct WorkoutBand: Identifiable, Equatable {
    let id: String
    /// Uppercased heading, or EMPTY when the block carries no label of its own
    /// and no structure worth naming — an unlabeled straight block renders as a
    /// bare card, exactly as it did before this ticket.
    let title: String
    let kind: WorkoutBandKind
    let rows: [WorkoutBandRow]
    /// Right-aligned subtotal, e.g. `≈ 14 MIN` or `96 MIN`.
    let timeLabel: String
    let seconds: Int
    let isEstimate: Bool

    var hasHeader: Bool { !title.isEmpty }

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

    /// One stored block → one section. Nothing is merged, split, reordered or
    /// relabelled; a block with no exercises simply has nothing to draw.
    static func bands(blocks: [Block], estimate: WorkoutDurationEstimate) -> [WorkoutBand] {
        blocks.filter { !$0.exercises.isEmpty }.map { block in
            let measured = estimate.seconds(forBlockID: block.id)
            return WorkoutBand(
                id: block.id,
                title: title(for: block),
                kind: kind(for: block),
                rows: block.exercises.map { row(for: $0, estimate: estimate) },
                timeLabel: measured?.label ?? "",
                seconds: measured?.seconds ?? 0,
                isEstimate: measured?.isEstimate ?? false
            )
        }
    }

    private static func row(for exercise: Exercise, estimate: WorkoutDurationEstimate) -> WorkoutBandRow {
        WorkoutBandRow(
            id: exercise.id,
            name: exercise.name,
            modality: WorkoutSportHonesty.modality(for: exercise),
            prescription: WorkoutBandPrescription.line(
                for: exercise,
                estimate: estimate.seconds(forExerciseID: exercise.id)
            ),
            exercise: exercise
        )
    }
}
