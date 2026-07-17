//
//  SocialImportDetailPreviewView.swift
//  AmakaFlow
//
//  Post-ingest review — same layout as Library detail (SPEC.md § Create sheet → Workout detail).
//  Ground truth: design-handoff/screenshots/dd-detail-dark.png
//

import SwiftUI

struct SocialImportDetailPreviewView: View {
    @ObservedObject var viewModel: SocialImportViewModel
    let draft: SocialImportDraft
    var onLibraryReload: () -> Void
    var onDismiss: () -> Void

    @State private var previewWorkout: Workout

    init(
        viewModel: SocialImportViewModel,
        draft: SocialImportDraft,
        onLibraryReload: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.draft = draft
        self.onLibraryReload = onLibraryReload
        self.onDismiss = onDismiss
        _previewWorkout = State(initialValue: draft.toPreviewWorkout())
    }

    var body: some View {
        UnifiedWorkoutDetailView(
            workout: previewWorkout,
            importContext: WorkoutDetailImportContext(
                viewModel: viewModel,
                onLibraryReload: onLibraryReload
            ),
            onClose: onDismiss
        )
        .onChange(of: viewModel.draft) { _, newDraft in
            guard let newDraft else { return }
            previewWorkout = newDraft.toPreviewWorkout()
        }
        .onChange(of: viewModel.phase) { _, phase in
            guard case .saved(let workoutId) = phase else { return }
            previewWorkout = Workout(
                id: workoutId,
                name: previewWorkout.name,
                sport: previewWorkout.sport,
                duration: previewWorkout.duration,
                blocks: previewWorkout.blocks,
                description: previewWorkout.description,
                source: previewWorkout.source,
                sourceUrl: previewWorkout.sourceUrl,
                creatorName: previewWorkout.creatorName,
                createdAt: previewWorkout.createdAt
            )
        }
        .accessibilityIdentifier("social_import_detail_preview")
    }
}

/// Unsaved import — Start saves to Library first (proto toast: "Saved to My Workouts").
struct WorkoutDetailImportContext {
    @ObservedObject var viewModel: SocialImportViewModel
    var onLibraryReload: () -> Void

    var isSaved: Bool {
        if case .saved = viewModel.phase { return true }
        return false
    }
}
