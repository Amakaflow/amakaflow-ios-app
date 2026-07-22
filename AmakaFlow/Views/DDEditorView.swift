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
    var onBackfillSaved: (() -> Void)?

    init(mode: DDEditorMode = .new, workout: Workout? = nil, onBackfillSaved: (() -> Void)? = nil) {
        self.mode = mode
        self.workout = workout
        self.onBackfillSaved = onBackfillSaved
    }

    var body: some View {
        if mode == .backfill {
            DDEditorLegacyView(mode: mode, workout: workout, onBackfillSaved: onBackfillSaved)
        } else {
            EditorV2View(mode: mode, workout: workout)
        }
    }
}

#if DEBUG
#Preview { DDEditorView(mode: .backfill) }
#endif
