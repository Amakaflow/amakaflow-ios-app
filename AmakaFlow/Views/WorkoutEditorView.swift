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

    /// Create mode — Editor v2 empty + optional format chips (AMA-2307 / ADR-017).
    init() {
        mode = .new
        workout = nil
    }

    /// Edit mode — Editor v2 calm list (AMA-2307 / ADR-017).
    init(workout: Workout) {
        mode = .edit
        self.workout = workout
    }

    var body: some View {
        DDEditorView(mode: mode, workout: workout)
    }
}

#if DEBUG
#Preview {
    WorkoutEditorView()
        .preferredColorScheme(.dark)
}
#endif
