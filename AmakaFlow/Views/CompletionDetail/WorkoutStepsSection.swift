//
//  WorkoutStepsSection.swift
//  AmakaFlow
//
//  Displays workout steps/exercises in completion detail view (AMA-224)
//

import SwiftUI

struct WorkoutStepsSection: View {
    let steps: [WorkoutStepItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Steps")
                .font(.headline)
                .foregroundColor(.primary)

            if steps.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(steps) { step in
                        stepRow(step)
                    }
                }
            }
        }
        .padding()
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }

    // MARK: - Step Row

    private func stepRow(_ step: WorkoutStepItem) -> some View {
        HStack(spacing: 12) {
            // Step number badge
            Text("\(step.stepNumber)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(step.iconColor)
                .clipShape(Circle())

            // Icon
            Image(systemName: step.icon)
                .foregroundColor(step.iconColor)
                .frame(width: 20)

            // Name and detail
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(step.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let target = step.target, !target.isEmpty {
                    Text(target)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("No workout steps recorded")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        WorkoutStepsSection(steps: [
            WorkoutStepItem(stepNumber: 1, name: "Warm Up", detail: "5 min", target: "Easy pace", icon: "flame", iconColor: .orange),
            WorkoutStepItem(stepNumber: 2, name: "Squats", detail: "3 × 10 reps", target: nil, icon: "dumbbell.fill", iconColor: .purple),
            WorkoutStepItem(stepNumber: 3, name: "Lunges", detail: "3 × 12 reps", target: nil, icon: "dumbbell.fill", iconColor: .purple),
            WorkoutStepItem(stepNumber: 4, name: "Leg Press", detail: "4 × 8 reps @ 200 lbs", target: nil, icon: "dumbbell.fill", iconColor: .purple),
            WorkoutStepItem(stepNumber: 5, name: "Cool Down", detail: "5 min", target: "Stretch", icon: "snowflake", iconColor: .blue)
        ])

        WorkoutStepsSection(steps: [])
    }
    .padding()
    .background(Theme.Colors.background)
}
