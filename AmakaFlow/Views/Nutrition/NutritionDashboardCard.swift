//
//  NutritionDashboardCard.swift
//  AmakaFlow
//
//  Dashboard card showing "Today's Nutrition" on the home screen (AMA-1290).
//

import SwiftUI

struct NutritionDashboardCard: View {
    @ObservedObject var viewModel: NutritionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.accentGreen)

                Text("Today's Nutrition")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            if !viewModel.settings.isEnabled {
                disabledState
            } else if viewModel.todayCalories == 0 && viewModel.todayProtein == 0 && viewModel.todayWater == 0 {
                emptyState
            } else {
                nutritionContent
            }

            // Source attribution
            if let source = viewModel.sourceAppName, viewModel.settings.isEnabled {
                Text("From \(source)")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
        .accessibilityIdentifier("nutrition_dashboard_card")
    }

    // MARK: - Disabled State

    private var disabledState: some View {
        HStack {
            Text("Nutrition tracking is off")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()

            Text("Settings")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.accentBlue)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("No nutrition data yet today")
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.textSecondary)
    }

    // MARK: - Nutrition Content

    private var nutritionContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Qualitative label (always shown)
            Text(viewModel.qualitativeLabel)
                .font(Theme.Typography.title3)
                .foregroundColor(viewModel.qualitativeLabelColor)

            // Protein progress bar (when numeric or protein-only)
            if viewModel.shouldShowProtein {
                proteinProgressRow
            }

            // Full macros
            if viewModel.shouldShowAllMacros {
                macrosRow
            }

            // Calories
            if viewModel.shouldShowCalories {
                HStack {
                    Text("\(Int(viewModel.todayCalories)) kcal")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer()
                }
            }

            // Water mini indicator
            if viewModel.todayWater > 0 {
                waterMiniRow
            }
        }
    }

    // MARK: - Protein Progress

    private var proteinProgressRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Protein")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text("\(Int(viewModel.todayProtein))g / \(Int(viewModel.settings.proteinTargetGrams))g")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.surfaceElevated)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(viewModel.proteinProgressColor)
                        .frame(width: geometry.size.width * viewModel.proteinProgress, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Macros Row

    private var macrosRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            macroItem(label: "Carbs", value: "\(Int(viewModel.todayCarbs))g")
            macroItem(label: "Fat", value: "\(Int(viewModel.todayFat))g")
        }
    }

    private func macroItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Water Mini

    private var waterMiniRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "drop.fill")
                .font(.system(size: 10))
                .foregroundColor(Theme.Colors.accentBlue)
            Text("\(Int(viewModel.todayWater))mL")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

#Preview {
    NutritionDashboardCard(viewModel: NutritionViewModel())
        .padding()
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
