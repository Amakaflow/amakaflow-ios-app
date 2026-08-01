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

    /// Create mode — Editor v2 empty + optional format chips (AMA-2307 / ADR-017).
    init() {
        mode = .new
        workout = nil
        preset = nil
    }

    /// Preset mode — a new Editor v2 draft with canonical naming ownership.
    init(preset: WorkoutTypeItem) {
        mode = .new
        workout = nil
        self.preset = preset
    }

    /// Edit mode — Editor v2 calm list (AMA-2307 / ADR-017).
    init(workout: Workout) {
        mode = .edit
        self.workout = workout
        preset = nil
    }

    var body: some View {
        DDEditorView(mode: mode, workout: workout, preset: preset)
    }
}

#if DEBUG
#Preview {
    WorkoutEditorView()
        .preferredColorScheme(.dark)
}
#endif
