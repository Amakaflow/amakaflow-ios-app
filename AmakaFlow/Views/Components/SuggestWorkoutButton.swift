//
//  SuggestWorkoutButton.swift
//  AmakaFlow
//
//  Prominent "Suggest Workout" button for the home screen (AMA-1265).
//

import SwiftUI

struct SuggestWorkoutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))

                Text("Suggest Workout")
                    .font(Theme.Typography.bodyBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                LinearGradient(
                    colors: [Theme.Colors.accentOrange, Theme.Colors.accentOrange.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(Theme.CornerRadius.lg)
        }
        // AMA-1842: stable a11y identifier for CJ-01 L3 XCUITest critical-journey suite.
        // Keep the legacy "suggest_workout_button" string in code search so that anyone
        // grepping the old ID lands here and discovers the rename.
        .accessibilityIdentifier("ama1842.suggest.button")
    }
}

#Preview {
    SuggestWorkoutButton(action: {})
        .padding()
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
