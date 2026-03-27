//
//  NutritionOnboardingView.swift
//  AmakaFlow
//
//  "Would you like nutrition awareness?" prompt (AMA-1292).
//  Not enabled by default - user must opt in.
//

import SwiftUI

struct NutritionOnboardingView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentGreen.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.Colors.accentGreen)
            }

            // Title
            Text("Nutrition Awareness")
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            // Description
            VStack(spacing: Theme.Spacing.md) {
                featureRow(
                    icon: "heart.text.square.fill",
                    text: "See how your fueling supports your training"
                )
                featureRow(
                    icon: "shield.checkered",
                    text: "Qualitative labels by default \u{2014} no calorie counting"
                )
                featureRow(
                    icon: "hand.raised.fill",
                    text: "You control exactly what\u{2019}s shown"
                )
                featureRow(
                    icon: "arrow.triangle.2.circlepath",
                    text: "Syncs with HealthKit \u{2014} works with MyFitnessPal & more"
                )
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()

            // Buttons
            VStack(spacing: Theme.Spacing.md) {
                Button {
                    viewModel.completeOnboarding(enableNutrition: true)
                    dismiss()
                } label: {
                    Text("Enable Nutrition Awareness")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.accentGreen)
                        .cornerRadius(Theme.CornerRadius.lg)
                }
                .accessibilityIdentifier("nutrition_enable_button")

                Button {
                    viewModel.skipOnboarding()
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                }
                .accessibilityIdentifier("nutrition_skip_button")
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .background(Theme.Colors.background.ignoresSafeArea())
        .accessibilityIdentifier("nutrition_onboarding_view")
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Theme.Colors.accentGreen)
                .frame(width: 28)

            Text(text)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    NutritionOnboardingView(viewModel: NutritionViewModel())
        .preferredColorScheme(.dark)
}
