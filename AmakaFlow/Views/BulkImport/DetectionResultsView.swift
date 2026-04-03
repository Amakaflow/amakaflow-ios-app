//
//  DetectionResultsView.swift
//  AmakaFlow
//
//  Step 2: Show detected workout items with confidence badges (AMA-1415)
//

import SwiftUI

struct DetectionResultsView: View {
    @ObservedObject var viewModel: BulkImportViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable list
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Header
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Detected Workouts")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text("\(viewModel.detectedItems.count) item(s) found")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.md)

                    // Detected item cards
                    ForEach(viewModel.detectedItems) { item in
                        DetectedItemCard(item: item)
                            .padding(.horizontal, Theme.Spacing.md)
                    }

                    // Error message
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.accentRed)
                            .padding(.horizontal, Theme.Spacing.md)
                    }

                    Spacer(minLength: Theme.Spacing.xl)
                }
            }

            // Bottom action bar
            VStack(spacing: 0) {
                Divider().background(Theme.Colors.borderLight)

                Button {
                    Task { await viewModel.matchExercises() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isLoading ? "Matching..." : "Continue to Matching")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
                }
                .disabled(viewModel.isLoading || viewModel.detectedItems.isEmpty)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }
}

// MARK: - Detected Item Card

struct DetectedItemCard: View {
    let item: DetectedItem

    private var confidenceColor: Color {
        if item.confidence >= 80 { return Theme.Colors.accentGreen }
        if item.confidence >= 50 { return Theme.Colors.accentOrange }
        return Theme.Colors.accentRed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(item.parsedTitle ?? item.sourceRef)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)

                    if let exerciseCount = item.parsedExerciseCount {
                        Text("\(exerciseCount) exercises")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Spacer()

                // Confidence badge
                Text("\(item.confidence)%")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(confidenceColor)
                    .cornerRadius(Theme.CornerRadius.sm)
            }

            // Errors
            if let errors = item.errors, !errors.isEmpty {
                ForEach(errors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentRed)
                }
            }

            // Warnings
            if let warnings = item.warnings, !warnings.isEmpty {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentOrange)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
    }
}
