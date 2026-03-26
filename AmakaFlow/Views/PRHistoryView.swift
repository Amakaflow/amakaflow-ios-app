//
//  PRHistoryView.swift
//  AmakaFlow
//
//  List of all personal records grouped by exercise with dates and values.
//  AMA-1282
//

import Combine
import SwiftUI

struct PRHistoryView: View {
    @StateObject private var viewModel = PRHistoryViewModel()

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if viewModel.groupedPRs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.lg) {
                        ForEach(viewModel.groupedPRs, id: \.exerciseName) { group in
                            exerciseSection(group)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.lg)
                }
            }
        }
        .navigationTitle("Personal Records")
        .onAppear { viewModel.load() }
        .accessibilityIdentifier("pr_history_screen")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No Personal Records Yet")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Complete workouts with weight tracking to start setting PRs.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    // MARK: - Exercise Section

    private func exerciseSection(_ group: (exerciseName: String, records: [PersonalRecord])) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Exercise name header
            HStack {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "6C5CE7"))

                Text(group.exerciseName)
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .padding(.bottom, Theme.Spacing.xs)

            ForEach(group.records) { record in
                prRow(record)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func prRow(_ record: PersonalRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(record.typeLabel)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)

                Text(record.formattedValue)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Color(hex: "FFD700"))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text(record.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)

                if let workoutName = record.workoutName {
                    Text(workoutName)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - ViewModel

@MainActor
class PRHistoryViewModel: ObservableObject {
    @Published var groupedPRs: [(exerciseName: String, records: [PersonalRecord])] = []

    private let prService = PRDetectionService()

    func load() {
        groupedPRs = prService.prsByExercise()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PRHistoryView()
    }
    .preferredColorScheme(.dark)
}
