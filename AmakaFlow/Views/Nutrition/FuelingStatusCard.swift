//
//  FuelingStatusCard.swift
//  AmakaFlow
//
//  Green/yellow/red fueling status card with progress bars (AMA-1293).
//  Shows protein, calories, and hydration progress toward daily targets.
//

import SwiftUI

struct FuelingStatusCard: View {
    @ObservedObject var viewModel: FuelingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header row
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: viewModel.fuelingStatus.icon)
                    .font(.system(size: 20))
                    .foregroundColor(viewModel.fuelingStatus.color)

                Text("Fueling Status")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Theme.Colors.textSecondary)
                }
            }

            // Status message
            Text(viewModel.message)
                .font(Theme.Typography.body)
                .foregroundColor(viewModel.fuelingStatus.color)

            // Progress bars
            VStack(spacing: Theme.Spacing.sm) {
                FuelingProgressRow(
                    label: "Protein",
                    icon: "fork.knife",
                    pct: viewModel.proteinPct,
                    color: progressColor(for: viewModel.proteinPct, threshold: 70)
                )

                FuelingProgressRow(
                    label: "Calories",
                    icon: "flame.fill",
                    pct: viewModel.caloriesPct,
                    color: progressColor(for: viewModel.caloriesPct, threshold: 60)
                )

                FuelingProgressRow(
                    label: "Hydration",
                    icon: "drop.fill",
                    pct: viewModel.hydrationPct,
                    color: progressColor(for: viewModel.hydrationPct, threshold: 60)
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                .stroke(viewModel.fuelingStatus.color.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.xl)
        .accessibilityIdentifier("fueling_status_card")
        .task {
            await viewModel.fetchFuelingStatus()
        }
    }

    private func progressColor(for pct: Double, threshold: Double) -> Color {
        if pct >= threshold { return Theme.Colors.accentGreen }
        if pct >= 40 { return Color(hex: "F59E0B") }
        return Theme.Colors.accentRed
    }
}

// MARK: - Progress Row

struct FuelingProgressRow: View {
    let label: String
    let icon: String
    let pct: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)

                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer()

                Text("\(Int(min(pct, 999)))%")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.surfaceElevated)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(
                            width: min(CGFloat(pct / 100) * geometry.size.width, geometry.size.width),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview {
    let vm = FuelingViewModel()
    VStack {
        FuelingStatusCard(viewModel: vm)
    }
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
