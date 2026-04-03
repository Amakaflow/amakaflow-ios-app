//
//  ImportPreviewView.swift
//  AmakaFlow
//
//  Step 4: Preview workouts before importing with selection controls (AMA-1415)
//

import SwiftUI

struct ImportPreviewView: View {
    @ObservedObject var viewModel: BulkImportViewModel

    private var selectedCount: Int {
        viewModel.previewWorkouts.filter { $0.selected }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Stats summary
            if let stats = viewModel.importStats {
                statsRow(stats: stats)
            }

            // Workout list
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text("Preview")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Spacer()

                        Text("\(selectedCount) selected")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.md)

                    ForEach(viewModel.previewWorkouts) { workout in
                        PreviewWorkoutCard(workout: workout) {
                            viewModel.toggleWorkoutSelection(workout.id)
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
                    Task { await viewModel.executeImport() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isLoading ? "Starting Import..." : "Import \(selectedCount) Workout\(selectedCount == 1 ? "" : "s")")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(selectedCount > 0 ? Theme.Colors.accentBlue : Theme.Colors.borderMedium)
                    .cornerRadius(Theme.CornerRadius.md)
                }
                .disabled(viewModel.isLoading || selectedCount == 0)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }

    // MARK: - Stats Row

    private func statsRow(stats: ImportStats) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                statCard(value: stats.totalDetected, label: "Detected", icon: "doc.text.magnifyingglass", color: Theme.Colors.textSecondary)
                statCard(value: stats.totalSelected, label: "Selected", icon: "checkmark.circle", color: Theme.Colors.accentBlue)
                statCard(value: stats.duplicatesFound, label: "Duplicates", icon: "doc.on.doc", color: Theme.Colors.accentOrange)
                statCard(value: stats.validationErrors, label: "Errors", icon: "exclamationmark.circle", color: Theme.Colors.accentRed)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Colors.surface)
    }

    private func statCard(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text("\(value)")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(minWidth: 72)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surfaceElevated)
        .cornerRadius(Theme.CornerRadius.sm)
    }
}

// MARK: - Preview Workout Card

struct PreviewWorkoutCard: View {
    let workout: PreviewWorkout
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    // Selection checkbox
                    Image(systemName: workout.selected ? "checkmark.square.fill" : "square")
                        .foregroundColor(workout.selected ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(workout.title)
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            if workout.isDuplicate {
                                Text("Duplicate")
                                    .font(Theme.Typography.footnote)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, Theme.Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Theme.Colors.accentOrange)
                                    .cornerRadius(4)
                            }
                        }

                        Text("\(workout.exerciseCount) exercises\(workout.blockCount.map { ", \($0) blocks" } ?? "")")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer()
                }

                // Validation issues
                if let issues = workout.validationIssues, !issues.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(issues) { issue in
                            Label(issue.message, systemImage: issueIcon(issue.severity))
                                .font(Theme.Typography.footnote)
                                .foregroundColor(issueColor(issue.severity))
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(workout.selected ? Theme.Colors.accentBlue.opacity(0.08) : Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(workout.selected ? Theme.Colors.accentBlue.opacity(0.4) : Theme.Colors.borderLight, lineWidth: 1)
            )
        }
    }

    private func issueIcon(_ severity: String) -> String {
        switch severity {
        case "error": return "exclamationmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }

    private func issueColor(_ severity: String) -> Color {
        switch severity {
        case "error": return Theme.Colors.accentRed
        case "warning": return Theme.Colors.accentOrange
        default: return Theme.Colors.textSecondary
        }
    }
}
