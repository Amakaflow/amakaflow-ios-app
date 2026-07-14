//
//  StrengthBackfillView.swift
//  AmakaFlow
//
//  AMA-2290: Fast manual post-stop backfill for exercises / sets / reps / weights.
//  AI suggestions are never required to save.
//

import SwiftUI

struct StrengthBackfillView: View {
    @Binding var drafts: [StrengthBackfillExerciseDraft]
    var onSave: () -> Void
    var isSaving: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Log sets")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("af_strength_backfill_title")

                Text("Manual entry — AI optional. Save anytime.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("af_strength_backfill_hint")
            }

            ForEach($drafts) { $exercise in
                exerciseCard($exercise)
            }

            Button(action: onSave) {
                HStack(spacing: Theme.Spacing.sm) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Theme.Colors.surface)
                    }
                    Text(isSaving ? "Saving…" : "Save sets")
                        .font(Theme.Typography.bodyBold)
                }
                .foregroundColor(Theme.Colors.surface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.textPrimary)
                .clipShape(Capsule())
            }
            .disabled(isSaving)
            .accessibilityIdentifier("af_strength_backfill_save")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
        .accessibilityIdentifier("af_strength_backfill")
    }

    private func exerciseCard(_ exercise: Binding<StrengthBackfillExerciseDraft>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TextField("Exercise", text: exercise.exerciseName)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
                .accessibilityIdentifier("af_strength_backfill_exercise_name")

            ForEach(exercise.sets) { $set in
                setRow($set)
            }

            Button {
                let next = (exercise.wrappedValue.sets.map(\.setNumber).max() ?? 0) + 1
                exercise.wrappedValue.sets.append(
                    StrengthBackfillSetDraft(setNumber: next, reps: exercise.wrappedValue.sets.last?.reps)
                )
            } label: {
                Label("Add set", systemImage: "plus.circle")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.accentBlue)
            }
            .accessibilityIdentifier("af_strength_backfill_add_set")
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.background)
        .cornerRadius(Theme.CornerRadius.sm)
    }

    private func setRow(_ set: Binding<StrengthBackfillSetDraft>) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("S\(set.wrappedValue.setNumber)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 28, alignment: .leading)

            TextField(
                "Reps",
                value: set.reps,
                format: .number
            )
            .keyboardType(.numberPad)
            .font(Theme.Typography.body)
            .padding(8)
            .background(Theme.Colors.surface)
            .cornerRadius(8)
            .accessibilityIdentifier("af_strength_backfill_reps")

            TextField(
                "Weight",
                value: set.weight,
                format: .number
            )
            .keyboardType(.decimalPad)
            .font(Theme.Typography.body)
            .padding(8)
            .background(Theme.Colors.surface)
            .cornerRadius(8)
            .accessibilityIdentifier("af_strength_backfill_weight")

            Picker("Unit", selection: set.unit) {
                Text("lbs").tag("lbs")
                Text("kg").tag("kg")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("af_strength_backfill_unit")
        }
    }
}

#if DEBUG
#Preview {
    StrengthBackfillView(
        drafts: .constant(
            StrengthBackfill.draft(
                from: [
                    .reps(sets: 3, reps: 8, name: "Bench Press", load: nil, restSec: 90, followAlongUrl: nil),
                    .reps(sets: 3, reps: 10, name: "Row", load: nil, restSec: 60, followAlongUrl: nil)
                ],
                existingSetLogs: nil
            )
        )
    ) {}
    .padding()
    .background(Theme.Colors.background)
}
#endif
