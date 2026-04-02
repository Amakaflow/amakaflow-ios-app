//
//  WorkoutPreviewCard.swift
//  AmakaFlow
//
//  Inline generated workout preview for coach chat (AMA-1410)
//

import SwiftUI

struct WorkoutPreviewCard: View {
    let workout: GeneratedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header
            HStack {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(Theme.Colors.accentBlue)
                    .font(.system(size: 14))

                Text(workout.name ?? "Generated Workout")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            // Metadata
            if workout.duration != nil || workout.difficulty != nil {
                HStack(spacing: Theme.Spacing.sm) {
                    if let duration = workout.duration {
                        Text(duration)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    if workout.duration != nil && workout.difficulty != nil {
                        Text("·")
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    if let difficulty = workout.difficulty {
                        Text(difficulty)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            Divider()
                .background(Theme.Colors.borderLight)

            // Exercises
            ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, exercise in
                HStack {
                    Text(exercise.name)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    if let sets = exercise.sets, let reps = exercise.reps {
                        Text("\(sets)×\(reps)")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.accentBlue)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.lg)
    }
}
