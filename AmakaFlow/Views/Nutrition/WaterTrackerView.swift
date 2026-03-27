//
//  WaterTrackerView.swift
//  AmakaFlow
//
//  Water logging with cup/glass visual metaphor (AMA-1291).
//

import SwiftUI

struct WaterTrackerView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                // Title area
                VStack(spacing: Theme.Spacing.sm) {
                    Text("\(Int(viewModel.todayWater))mL")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(Theme.Colors.accentBlue)

                    Text("of \(Int(viewModel.settings.waterTargetML))mL target")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.top, Theme.Spacing.xl)

                // Cup grid
                cupGrid
                    .padding(.horizontal, Theme.Spacing.lg)

                Spacer()

                // Add water button
                addWaterButton

                // Progress bar
                waterProgressBar
                    .padding(.horizontal, Theme.Spacing.lg)

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Water Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("water_tracker_view")
    }

    // MARK: - Cup Grid

    private var cupGrid: some View {
        let totalCups = viewModel.waterCupsTarget
        let filledCups = viewModel.waterCupsConsumed
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 5)

        return LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            ForEach(0..<totalCups, id: \.self) { index in
                cupView(isFilled: index < filledCups)
            }
        }
    }

    private func cupView(isFilled: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                .fill(isFilled ? Theme.Colors.accentBlue : Theme.Colors.surfaceElevated)
                .frame(height: 44)

            Image(systemName: isFilled ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 18))
                .foregroundColor(isFilled ? .white : Theme.Colors.textTertiary)
        }
        .animation(.easeInOut(duration: 0.2), value: isFilled)
    }

    // MARK: - Add Water Button

    private var addWaterButton: some View {
        Button {
            Task {
                await viewModel.logWater(milliliters: 250)
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                Text("+250mL")
                    .font(Theme.Typography.bodyBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(Theme.Colors.accentBlue)
            .cornerRadius(Theme.CornerRadius.lg)
        }
        .accessibilityIdentifier("water_add_250")
    }

    // MARK: - Progress Bar

    private var waterProgressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Hydration")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text("\(Int(viewModel.waterProgress * 100))%")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.Colors.surfaceElevated)
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.Colors.accentBlue)
                        .frame(width: geometry.size.width * viewModel.waterProgress, height: 10)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.waterProgress)
                }
            }
            .frame(height: 10)
        }
    }
}

#Preview {
    WaterTrackerView(viewModel: NutritionViewModel())
        .preferredColorScheme(.dark)
}
