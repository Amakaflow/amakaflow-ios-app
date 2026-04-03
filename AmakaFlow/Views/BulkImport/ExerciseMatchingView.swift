//
//  ExerciseMatchingView.swift
//  AmakaFlow
//
//  Step 3: Review and fix exercise name matches (AMA-1415)
//

import SwiftUI

struct ExerciseMatchingView: View {
    @ObservedObject var viewModel: BulkImportViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Stats bar
            if let stats = viewModel.matchStats {
                matchStatsBar(stats: stats)
            }

            // Scrollable exercise list
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Exercise Matches")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)

                    ForEach(viewModel.exerciseMatches) { match in
                        ExerciseMatchRow(match: match) { garminName in
                            viewModel.updateExerciseMapping(exerciseId: match.id, garminName: garminName)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }

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
                    Task { await viewModel.preview() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isLoading ? "Loading Preview..." : "Continue to Preview")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
                }
                .disabled(viewModel.isLoading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }

    // MARK: - Stats Bar

    private func matchStatsBar(stats: (matched: Int, needsReview: Int, total: Int)) -> some View {
        HStack(spacing: 0) {
            statCell(value: stats.matched, label: "Matched", color: Theme.Colors.accentGreen)
            Divider().frame(height: 36)
            statCell(value: stats.needsReview, label: "Need Review", color: Theme.Colors.accentOrange)
            Divider().frame(height: 36)
            statCell(value: stats.total, label: "Total", color: Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
    }

    private func statCell(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(Theme.Typography.title3)
                .foregroundColor(color)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Exercise Match Row

struct ExerciseMatchRow: View {
    let match: ExerciseMatch
    let onSelection: (String) -> Void

    private var statusIcon: String {
        switch match.status {
        case "matched": return "checkmark.circle.fill"
        case "needs_review": return "exclamationmark.triangle.fill"
        default: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch match.status {
        case "matched": return Theme.Colors.accentGreen
        case "needs_review": return Theme.Colors.accentOrange
        default: return Theme.Colors.accentRed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.originalName)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if let garminName = match.matchedGarminName {
                        Text(garminName)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Spacer()

                Text("\(match.confidence)%")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(statusColor)
            }

            // Suggestion picker for needs_review items
            if match.status == "needs_review", let suggestions = match.suggestions, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Suggestions:")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)

                    ForEach(suggestions, id: \.name) { suggestion in
                        Button {
                            onSelection(suggestion.name)
                        } label: {
                            HStack {
                                Text(suggestion.name)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Spacer()
                                Text("\(suggestion.confidence)%")
                                    .font(Theme.Typography.footnote)
                                    .foregroundColor(Theme.Colors.textSecondary)

                                if match.userSelection == suggestion.name {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.Colors.accentBlue)
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(match.userSelection == suggestion.name
                                        ? Theme.Colors.accentBlue.opacity(0.15)
                                        : Theme.Colors.surfaceElevated)
                            .cornerRadius(Theme.CornerRadius.sm)
                        }
                    }
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
