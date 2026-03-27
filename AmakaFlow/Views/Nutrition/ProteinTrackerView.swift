//
//  ProteinTrackerView.swift
//  AmakaFlow
//
//  Quick protein logging with progress toward daily target (AMA-1291).
//

import SwiftUI

struct ProteinTrackerView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                // Progress circle
                progressCircle
                    .padding(.top, Theme.Spacing.xl)

                // Status label
                Text(viewModel.qualitativeLabel)
                    .font(Theme.Typography.title3)
                    .foregroundColor(viewModel.qualitativeLabelColor)

                // Target info
                Text("Target: \(Int(viewModel.settings.proteinTargetGrams))g")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer()

                // Quick-add buttons
                quickAddButtons

                // Progress bar
                proteinProgressBar
                    .padding(.horizontal, Theme.Spacing.lg)

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Protein Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("protein_tracker_view")
    }

    // MARK: - Progress Circle

    private var progressCircle: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surfaceElevated, lineWidth: 12)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0, to: viewModel.proteinProgress)
                .stroke(viewModel.proteinProgressColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: viewModel.proteinProgress)

            VStack(spacing: 4) {
                Text("\(Int(viewModel.todayProtein))g")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("of \(Int(viewModel.settings.proteinTargetGrams))g")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    // MARK: - Quick Add Buttons

    private var quickAddButtons: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Quick Add")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                quickAddButton(grams: 20)
                quickAddButton(grams: 30)
                quickAddButton(grams: 40)
            }
        }
    }

    private func quickAddButton(grams: Int) -> some View {
        Button {
            Task {
                await viewModel.logProtein(grams: Double(grams))
            }
        } label: {
            VStack(spacing: 4) {
                Text("+\(grams)g")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(viewModel.proteinProgressColor.opacity(0.8))
            .cornerRadius(Theme.CornerRadius.lg)
        }
        .accessibilityIdentifier("protein_add_\(grams)")
    }

    // MARK: - Progress Bar

    private var proteinProgressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Progress")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text("\(Int(viewModel.proteinProgress * 100))%")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.Colors.surfaceElevated)
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.proteinProgressColor)
                        .frame(width: geometry.size.width * viewModel.proteinProgress, height: 10)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.proteinProgress)
                }
            }
            .frame(height: 10)
        }
    }
}

#Preview {
    ProteinTrackerView(viewModel: NutritionViewModel())
        .preferredColorScheme(.dark)
}
