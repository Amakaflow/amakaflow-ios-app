//
//  ExerciseRowView.swift
//  AmakaFlow
//
//  Single exercise row within a block section
//

import SwiftUI

struct ExerciseRowView: View {
    let exercise: Exercise
    var showSupersetIndicator: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Superset indicator bar
            if showSupersetIndicator {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.trailing, Theme.Spacing.sm)
            }

            // Name + rest
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let restSec = exercise.restSeconds, restSec > 0 {
                    Text("Rest \(restSec)s")
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Detail + load
            VStack(alignment: .trailing, spacing: 2) {
                let detail = exercise.formattedDetail
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.cyan)
                }

                if let load = exercise.formattedLoad {
                    Text(load)
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: 44)
    }
}

#Preview {
    VStack(spacing: 0) {
        ExerciseRowView(
            exercise: Exercise(
                name: "Back Squat",
                canonicalName: nil,
                sets: 4,
                reps: "8",
                durationSeconds: nil,
                load: ExerciseLoad(value: 100, unit: "kg"),
                restSeconds: 90,
                distance: nil,
                notes: nil,
                supersetGroup: nil
            ),
            showSupersetIndicator: false
        )
        Divider()
        ExerciseRowView(
            exercise: Exercise(
                name: "Pull-Up",
                canonicalName: nil,
                sets: 3,
                reps: "10",
                durationSeconds: nil,
                load: nil,
                restSeconds: nil,
                distance: nil,
                notes: nil,
                supersetGroup: 1
            ),
            showSupersetIndicator: true
        )
        Divider()
        ExerciseRowView(
            exercise: Exercise(
                name: "Plank",
                canonicalName: nil,
                sets: nil,
                reps: nil,
                durationSeconds: 60,
                load: nil,
                restSeconds: 30,
                distance: nil,
                notes: nil,
                supersetGroup: nil
            )
        )
    }
    .background(Theme.Colors.surface)
    .cornerRadius(Theme.CornerRadius.xl)
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
