//
//  WorkoutEditorView.swift
//  AmakaFlow
//
//  Thin wrapper around DDEditorView for create/edit flows (AMA-1232).
//

import SwiftUI

struct WorkoutEditorView: View {
    private let mode: DDEditorMode
    private let workout: Workout?
    private let preset: WorkoutTypeItem?
    private let builderV3Seed: BuilderV3TypeSeed?
    private let onBuilderV3ChangeType: (() -> Void)?

    /// Create mode — Editor v2 empty + optional format chips (AMA-2307 / ADR-017).
    init() {
        mode = .new
        workout = nil
        preset = nil
        builderV3Seed = nil
        onBuilderV3ChangeType = nil
    }

    /// Preset mode — a new Editor v2 draft with canonical naming ownership.
    init(preset: WorkoutTypeItem) {
        mode = .new
        workout = nil
        self.preset = preset
        builderV3Seed = nil
        onBuilderV3ChangeType = nil
    }

    /// Edit mode — Editor v2 calm list (AMA-2307 / ADR-017).
    init(workout: Workout) {
        mode = .edit
        self.workout = workout
        preset = nil
        builderV3Seed = nil
        onBuilderV3ChangeType = nil
    }

    /// Builder v3 (AMA-2372) — a new Editor v2 draft pre-seeded from the type
    /// picker; `onBuilderV3ChangeType` returns to the picker via the
    /// `TYPE · CHANGE` header button.
    init(builderV3Seed: BuilderV3TypeSeed, onBuilderV3ChangeType: @escaping () -> Void) {
        mode = .new
        workout = nil
        preset = nil
        self.builderV3Seed = builderV3Seed
        self.onBuilderV3ChangeType = onBuilderV3ChangeType
    }

    var body: some View {
        DDEditorView(
            mode: mode,
            workout: workout,
            preset: preset,
            builderV3Seed: builderV3Seed,
            onBuilderV3ChangeType: onBuilderV3ChangeType
        )
    }
}

#if DEBUG
#Preview {
    WorkoutEditorView()
        .preferredColorScheme(.dark)
}
#endif
