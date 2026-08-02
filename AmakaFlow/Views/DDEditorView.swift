//
//  DDEditorView.swift
//  AmakaFlow
//
//  AMA-2307: .edit / .importReview / .new → Editor v2; .backfill → legacy accordion.
//

import SwiftUI

struct DDEditorView: View {
    let mode: DDEditorMode
    var workout: Workout?
    var preset: WorkoutTypeItem?
    /// AMA-2372 — Builder v3 type-picker seed + its "return to picker" callback.
    var builderV3Seed: BuilderV3TypeSeed?
    var onBuilderV3ChangeType: (() -> Void)?
    var onBackfillSaved: (() -> Void)?

    init(
        mode: DDEditorMode = .new,
        workout: Workout? = nil,
        preset: WorkoutTypeItem? = nil,
        builderV3Seed: BuilderV3TypeSeed? = nil,
        onBuilderV3ChangeType: (() -> Void)? = nil,
        onBackfillSaved: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.workout = workout
        self.preset = preset
        self.builderV3Seed = builderV3Seed
        self.onBuilderV3ChangeType = onBuilderV3ChangeType
        self.onBackfillSaved = onBackfillSaved
    }

    var body: some View {
        if mode == .backfill {
            DDEditorLegacyView(mode: mode, workout: workout, onBackfillSaved: onBackfillSaved)
        } else {
            EditorV2View(
                mode: mode,
                workout: workout,
                preset: preset,
                builderV3Seed: builderV3Seed,
                onBuilderV3ChangeType: onBuilderV3ChangeType
            )
        }
    }
}

#if DEBUG
#Preview { DDEditorView(mode: .backfill) }
#endif
