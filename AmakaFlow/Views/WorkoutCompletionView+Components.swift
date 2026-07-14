//
//  WorkoutCompletionView+Components.swift
//  AmakaFlow
//
//  Extracted from WorkoutCompletionView to satisfy SwiftLint file/type length.
//

import SwiftUI

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)

                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }
}

// MARK: - Preview

#Preview {
    let sampleHR = (0..<20).map { sampleIndex in
        HeartRateSample(
            timestamp: Date().addingTimeInterval(Double(sampleIndex) * 30),
            value: Int.random(in: 120...160)
        )
    }

    return WorkoutCompletionView(
        viewModel: WorkoutCompletionViewModel(
            workoutName: "HIIT Cardio Blast",
            durationSeconds: 2700,
            deviceMode: .appleWatchPhone,
            calories: 320,
            avgHeartRate: 142,
            maxHeartRate: 175,
            heartRateSamples: sampleHR
        ) {},
        engine: WorkoutEngine.shared
    )
    .preferredColorScheme(.dark)
}
