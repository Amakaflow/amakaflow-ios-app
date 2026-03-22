//
//  ShoeComparisonView.swift
//  AmakaFlow
//
//  Shoe comparison analytics view (AMA-1147)
//

import SwiftUI

struct ShoeComparisonView: View {
    @StateObject private var viewModel = ShoeComparisonViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.shoes.isEmpty {
                    ProgressView("Loading shoe data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.shoes.isEmpty {
                    emptyState
                } else {
                    shoeList
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Shoe Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadShoes()
            }
        }
    }

    // MARK: - Shoe List

    private var shoeList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Summary
                HStack(spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(String(format: "%.1f km", viewModel.totalDistance))
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Total Distance")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        Text("\(viewModel.totalRuns)")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Total Runs")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)

                // Shoes
                ForEach(viewModel.shoes) { shoe in
                    shoeCard(shoe)
                }
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }

    private func shoeCard(_ shoe: ShoeStats) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(shoe.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if let brand = shoe.brand {
                        Text(brand)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                Spacer()

                if shoe.retiredAt != nil {
                    Text("Retired")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.surfaceElevated)
                        .cornerRadius(Theme.CornerRadius.sm)
                }
            }

            HStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f km", shoe.totalDistanceKm))
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Distance")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(shoe.totalRuns)")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Runs")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                if let pace = shoe.averagePaceMinKm {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f min/km", pace))
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Avg Pace")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            // Distance bar
            GeometryReader { geo in
                let maxDist = viewModel.shoes.map(\.totalDistanceKm).max() ?? 1
                let ratio = shoe.totalDistanceKm / maxDist
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.accentBlue)
                    .frame(width: geo.size.width * ratio, height: 6)
            }
            .frame(height: 6)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "shoe.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textSecondary)

            Text("No shoes tracked yet")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Add your running shoes to compare performance across different pairs.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
    }
}

#Preview {
    ShoeComparisonView()
        .preferredColorScheme(.dark)
}
