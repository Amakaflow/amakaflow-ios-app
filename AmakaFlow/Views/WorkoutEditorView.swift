//
//  WorkoutEditorView.swift
//  AmakaFlow
//
//  Workout creation and editing form (AMA-1232)
//

import SwiftUI

struct WorkoutEditorView: View {
    @StateObject private var viewModel: WorkoutEditorViewModel
    @Environment(\.dismiss) var dismiss

    /// Create mode
    init() {
        _viewModel = StateObject(wrappedValue: WorkoutEditorViewModel())
    }

    /// Edit mode — populate from existing workout
    init(workout: Workout) {
        _viewModel = StateObject(wrappedValue: WorkoutEditorViewModel(workout: workout))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Workout Name
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Workout Name")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)

                        TextField("e.g. Full Body Strength", text: $viewModel.name)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
                            )
                            .cornerRadius(Theme.CornerRadius.md)
                            .accessibilityIdentifier("workout_name_field")
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    // Sport Type Picker
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Sport Type")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)

                        HStack {
                            Picker("Sport", selection: $viewModel.sport) {
                                ForEach(WorkoutEditorViewModel.sportOptions, id: \.0) { sport, label in
                                    Text(label).tag(sport)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.Colors.accentBlue)

                            Spacer()
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )
                        .cornerRadius(Theme.CornerRadius.md)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    // Intervals Section
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        HStack {
                            Text("Exercises / Intervals")
                                .font(Theme.Typography.title2)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Spacer()

                            Text("\(viewModel.intervals.count)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)

                        if viewModel.intervals.isEmpty {
                            emptyIntervalsView
                                .padding(.horizontal, Theme.Spacing.lg)
                        } else {
                            intervalsList
                        }

                        // Add Interval Button
                        Button(action: { viewModel.addInterval() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                Text("Add Exercise")
                                    .font(Theme.Typography.bodyBold)
                            }
                            .foregroundColor(Theme.Colors.accentBlue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.Colors.accentBlue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(Theme.Colors.accentBlue.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(Theme.CornerRadius.md)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .accessibilityIdentifier("add_interval_button")
                    }

                    // Error Message
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                            Text(error)
                                .font(Theme.Typography.caption)
                        }
                        .foregroundColor(Theme.Colors.accentRed)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.accentRed.opacity(0.1))
                        .cornerRadius(Theme.CornerRadius.md)
                        .padding(.horizontal, Theme.Spacing.lg)
                    }

                    // Save Button
                    Button(action: {
                        Task { await viewModel.save() }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                            }
                            Text(viewModel.isEditMode ? "Save Changes" : "Create Workout")
                                .font(Theme.Typography.bodyBold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            LinearGradient(
                                colors: [Theme.Colors.accentBlue, Theme.Colors.accentGreen],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(Theme.CornerRadius.md)
                    }
                    .disabled(viewModel.isSaving)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .accessibilityIdentifier("save_workout_button")

                    Spacer(minLength: 40)
                }
                .padding(.top, Theme.Spacing.md)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle(viewModel.isEditMode ? "Edit Workout" : "New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .onChange(of: viewModel.didSave) { _, saved in
                if saved { dismiss() }
            }
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("workout_editor_screen")
            }
        }
    }

    // MARK: - Subviews

    private var emptyIntervalsView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.textSecondary)

            Text("No exercises yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Tap \"Add Exercise\" to build your workout")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.xl)
    }

    private var intervalsList: some View {
        VStack(spacing: 12) {
            ForEach(Array(viewModel.intervals.enumerated()), id: \.offset) { index, _ in
                IntervalEditorCard(interval: $viewModel.intervals[index], index: index) {
                    withAnimation {
                        viewModel.removeInterval(at: IndexSet(integer: index))
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }
}

// MARK: - Interval Editor Card

struct IntervalEditorCard: View {
    @Binding var interval: WorkoutSaveInterval
    let index: Int
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header with step number and delete
            HStack {
                Text("Exercise \(index + 1)")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.accentBlue)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.accentRed)
                }
                .accessibilityIdentifier("delete_interval_\(index)")
            }

            // Exercise Name
            TextField("Exercise name", text: Binding(
                get: { interval.name ?? "" },
                set: { interval.name = $0 }
            ))
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.textPrimary)
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.surfaceElevated)
            .cornerRadius(Theme.CornerRadius.sm)
            .accessibilityIdentifier("interval_name_\(index)")

            // Sets / Reps / Rest row
            HStack(spacing: Theme.Spacing.sm) {
                NumberFieldColumn(label: "Sets", value: Binding(
                    get: { interval.sets ?? 3 },
                    set: { interval.sets = $0 }
                ))

                NumberFieldColumn(label: "Reps", value: Binding(
                    get: { interval.reps ?? 10 },
                    set: { interval.reps = $0 }
                ))

                NumberFieldColumn(label: "Rest (s)", value: Binding(
                    get: { interval.restSeconds ?? 60 },
                    set: { interval.restSeconds = $0 }
                ))
            }

            // Duration (optional)
            HStack(spacing: Theme.Spacing.sm) {
                NumberFieldColumn(label: "Duration (s)", value: Binding(
                    get: { interval.seconds ?? 0 },
                    set: { interval.seconds = $0 == 0 ? nil : $0 }
                ))

                // Load / Weight
                VStack(alignment: .leading, spacing: 4) {
                    Text("Load / Weight")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    TextField("e.g. 135 lbs", text: Binding(
                        get: { interval.load ?? "" },
                        set: { interval.load = $0.isEmpty ? nil : $0 }
                    ))
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surfaceElevated)
                    .cornerRadius(Theme.CornerRadius.sm)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }
}

// MARK: - Number Field Column

struct NumberFieldColumn: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.surfaceElevated)
                .cornerRadius(Theme.CornerRadius.sm)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutEditorView()
        .preferredColorScheme(.dark)
}
