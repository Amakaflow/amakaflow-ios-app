//
//  CreateWithAIPromptView.swift
//  AmakaFlow
//
//  Prompt-first entry point for creating an AI workout.
//

import SwiftUI

struct CreateWithAIPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SuggestWorkoutViewModel
    @State private var notes = ""
    @State private var durationMinutes: Int?
    @State private var isShowingSuggestion = false

    private let onSaved: () -> Void
    private let durationOptions = [30, 45, 60]

    init(
        viewModel: SuggestWorkoutViewModel? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? SuggestWorkoutViewModel())
        self.onSaved = onSaved
    }

    var body: some View {
        if isShowingSuggestion {
            SuggestWorkoutView(
                viewModel: viewModel,
                onWorkoutStarted: onSaved
            )
        } else {
            promptForm
        }
    }

    private var promptForm: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Describe a workout")
                                .afH1()
                            Text("Tell the coach what you want to do. Add a duration if you have one.")
                                .afMuted()
                        }

                        AFCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                AFLabel(text: "Workout notes")

                                ZStack(alignment: .topLeading) {
                                    if notes.isEmpty {
                                        Text("For example: an easy full-body workout with extra core work")
                                            .font(Theme.Typography.body)
                                            .foregroundColor(Theme.Colors.textTertiary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 8)
                                            .allowsHitTesting(false)
                                    }

                                    TextEditor(text: $notes)
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 150)
                                        .accessibilityIdentifier("create_with_ai_prompt_field")
                                }
                                .padding(8)
                                .background(DailyDriver.card)
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: Theme.CornerRadius.lg,
                                        style: .continuous
                                    )
                                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: Theme.CornerRadius.lg,
                                        style: .continuous
                                    )
                                )
                            }
                        }

                        AFCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                AFLabel(text: "Duration (optional)")

                                Picker("Duration", selection: $durationMinutes) {
                                    Text("Any").tag(nil as Int?)
                                    ForEach(durationOptions, id: \.self) { minutes in
                                        Text("\(minutes) min").tag(Optional(minutes))
                                    }
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("create_with_ai_duration")
                            }
                        }

                        Button {
                            generateWorkout()
                        } label: {
                            Label("Generate", systemImage: "sparkles")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                        .disabled(trimmedNotes.isEmpty)
                        .accessibilityIdentifier("create_with_ai_generate")
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            .navigationTitle("Create with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateWorkout() {
        guard !trimmedNotes.isEmpty else { return }
        isShowingSuggestion = true
        viewModel.requestSuggestionFromPrompt(
            notes: trimmedNotes,
            durationMinutes: durationMinutes,
            focusMuscleGroups: nil
        )
    }
}

#if DEBUG
#Preview {
    CreateWithAIPromptView()
        .environmentObject(WorkoutsViewModel())
}
#endif
