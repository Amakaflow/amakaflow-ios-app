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

    /// Create mode — opens block picker first (dd-editor-new-dark.png).
    init() {
        mode = .new
        workout = nil
    }

    /// Edit mode — populate from existing workout (dd-editor-dark.png).
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
