//
//  SocialImportPreviewView.swift
//  AmakaFlow
//
//  AMA-2285: editable preview before Library save.
//  AI never gatekeeps Edit — title and exercises are always editable.
//

import SwiftUI

struct SocialImportPreviewView: View {
    @ObservedObject var viewModel: SocialImportViewModel
    let draft: SocialImportDraft
    var onSaved: (() -> Void)?

    @State private var title: String = ""
    @State private var exercises: [SocialImportExercise] = []

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Workout title", text: $title)
                        .font(Theme.Typography.bodyBold)
                        .disabled(!viewModel.canEdit)
                        .accessibilityIdentifier("social_import_preview_title")
                        .onChange(of: title) { _, newValue in
                            viewModel.updateTitle(newValue)
                        }

                    WorkoutSourceBadge(source: draft.platform.workoutSourceRawValue)
                }
            } header: {
                Text("Preview")
            } footer: {
                Text("Edit freely before saving — import never blocks edits.")
            }

            // AMA-2297: thin "From post" trust block — creator / caption / source URL.
            if draft.postProvenance != nil || draft.sourceURL != nil {
                Section {
                    fromPostBlock
                } header: {
                    Text("From post")
                }
            }

            if let note = draft.equipmentNote {
                Section {
                    Label(note, systemImage: draft.equipmentEmpty ? "exclamationmark.circle" : "dumbbell.fill")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("social_import_equipment_banner")
                } header: {
                    Text(draft.equipmentEmpty ? "Equipment" : "Adapted to your equipment")
                }
            }

            Section {
                ForEach(Array(exercises.indices), id: \.self) { index in
                    exerciseRow(at: index)
                }
                .onDelete(perform: deleteExercises)

                if viewModel.canEdit {
                    Button {
                        viewModel.addExercise()
                        syncFromViewModel()
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("social_import_add_exercise")
                }
            } header: {
                Text("Exercises")
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        if viewModel.phase == .saving {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(saveButtonLabel)
                    }
                }
                .disabled(viewModel.phase == .saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("social_import_save")
            }

            if case .failed(let failure) = viewModel.phase {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(failure.title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.accentOrange)
                        Text(failure.userMessage)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .accessibilityIdentifier("social_import_preview_error")
                }
            }

            if case .saved = viewModel.phase {
                Section {
                    Label("Saved to Library", systemImage: "checkmark.circle.fill")
                        .foregroundColor(Theme.Colors.accentGreen)
                        .accessibilityIdentifier("social_import_saved")
                }
            }
        }
        .onAppear {
            title = draft.title
            exercises = draft.exercises
        }
        .onChange(of: viewModel.draft) { _, newDraft in
            guard let newDraft else { return }
            exercises = newDraft.exercises
            if title != newDraft.title {
                title = newDraft.title
            }
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if case .saved = newPhase {
                onSaved?()
            }
        }
        .accessibilityIdentifier("social_import_preview")
    }

    @ViewBuilder
    private var fromPostBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.postProvenance?.creatorDisplay ?? "creator unknown")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
                .accessibilityIdentifier("social_import_from_post_creator")

            if let snippet = draft.postProvenance?.contentSnippet {
                Text(snippet)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("social_import_from_post_snippet")
            }

            if let sourceURL = draft.sourceURL,
               let url = URL(string: sourceURL) {
                Link(destination: url) {
                    Label(sourceURL, systemImage: "link")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentBlue)
                        .lineLimit(1)
                }
                .accessibilityIdentifier("social_import_from_post_url")
            }
        }
        .accessibilityIdentifier("social_import_from_post")
    }

    private var saveButtonLabel: String {
        switch viewModel.phase {
        case .saving: return "Saving…"
        case .saved: return "Saved"
        default: return "Save to Library"
        }
    }

    @ViewBuilder
    private func exerciseRow(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Exercise name", text: nameBinding(at: index))
                .disabled(!viewModel.canEdit)
                .accessibilityIdentifier("social_import_exercise_name")

            HStack {
                TextField("Sets", text: setsBinding(at: index))
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 64)
                    .disabled(!viewModel.canEdit)
                Text("×")
                    .foregroundColor(Theme.Colors.textSecondary)
                TextField("Reps", text: repsBinding(at: index))
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 64)
                    .disabled(!viewModel.canEdit)
                Spacer()
            }
            .font(Theme.Typography.caption)
        }
        .padding(.vertical, 4)
    }

    private func nameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { exercises[index].name },
            set: { newValue in
                exercises[index].name = newValue
                pushExercise(at: index)
            }
        )
    }

    private func setsBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { exercises[index].sets.map(String.init) ?? "" },
            set: { newValue in
                exercises[index].sets = Int(newValue)
                pushExercise(at: index)
            }
        )
    }

    private func repsBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { exercises[index].reps.map(String.init) ?? "" },
            set: { newValue in
                exercises[index].reps = Int(newValue)
                pushExercise(at: index)
            }
        )
    }

    private func pushExercise(at index: Int) {
        guard exercises.indices.contains(index) else { return }
        let exercise = exercises[index]
        viewModel.updateExercise(
            id: exercise.id,
            name: exercise.name,
            sets: exercise.sets,
            reps: exercise.reps,
            seconds: exercise.seconds,
            notes: exercise.notes
        )
    }

    private func deleteExercises(at offsets: IndexSet) {
        guard viewModel.canEdit else { return }
        for index in offsets {
            let id = exercises[index].id
            viewModel.removeExercise(id: id)
        }
        syncFromViewModel()
    }

    private func syncFromViewModel() {
        exercises = viewModel.draft?.exercises ?? exercises
    }

    private func save() {
        viewModel.updateTitle(title)
        Task {
            await viewModel.saveToLibrary()
        }
    }
}
