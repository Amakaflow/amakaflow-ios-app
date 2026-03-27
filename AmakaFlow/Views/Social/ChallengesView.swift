//
//  ChallengesView.swift
//  AmakaFlow
//
//  Browse active and available challenges, filter by type (AMA-1276)
//

import SwiftUI

struct ChallengesView: View {
    @StateObject private var viewModel = ChallengesViewModel()
    @State private var showingCreateSheet = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.challenges.isEmpty {
                ProgressView("Loading challenges...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.challenges.isEmpty && viewModel.errorMessage == nil {
                emptyState
            } else {
                challengesList
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .refreshable {
            await viewModel.loadChallenges()
        }
        .task {
            if viewModel.challenges.isEmpty {
                await viewModel.loadChallenges()
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateChallengeView(viewModel: viewModel)
        }
        .overlay {
            if viewModel.showCelebration, let badge = viewModel.completedBadge {
                ChallengeCompletionView(badge: badge) {
                    viewModel.dismissCelebration()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text("Challenges")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }

            // Type filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    filterChip(title: "All", isSelected: viewModel.selectedTypeFilter == nil) {
                        viewModel.setTypeFilter(nil)
                    }

                    ForEach(ChallengeType.allCases) { type in
                        filterChip(
                            title: type.displayName,
                            isSelected: viewModel.selectedTypeFilter == type,
                            color: colorForType(type)
                        ) {
                            viewModel.setTypeFilter(type)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Challenges List

    private var challengesList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                header
                    .padding(.top, Theme.Spacing.sm)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                        .padding(.horizontal, Theme.Spacing.md)
                }

                ForEach(viewModel.filteredChallenges) { challenge in
                    NavigationLink {
                        ChallengeDetailView(
                            challengeId: challenge.id,
                            viewModel: viewModel
                        )
                    } label: {
                        challengeCard(challenge)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 100)
        }
    }

    // MARK: - Challenge Card

    private func challengeCard(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(challenge.type.displayName + (challenge.isTeamMode ? " \u{00B7} Team" : ""))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(challenge.participantCount)")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("participants")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            if let percentage = challenge.myProgressPercentage, challenge.isJoined {
                ProgressView(value: min(percentage / 100.0, 1.0))
                    .tint(colorForType(challenge.type))

                HStack {
                    Text("\(Int(percentage))% complete")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary)

                    Spacer()

                    Text(daysRemaining(challenge.endDate))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            } else {
                HStack {
                    Text(dateRange(challenge.startDate, challenge.endDate))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary)

                    Spacer()

                    if !challenge.isJoined {
                        Text("Tap to join")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorForType(challenge.type))
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(colorForType(challenge.type).opacity(0.5), lineWidth: 2)
        )
        .cornerRadius(12)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.accentBlue)

            Text("No challenges yet")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Create a challenge or wait for one to be posted.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showingCreateSheet = true
            } label: {
                Text("Create Challenge")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(10)
            }
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Filter Chip

    private func filterChip(
        title: String,
        isSelected: Bool,
        color: Color = Theme.Colors.accentBlue,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? color : Theme.Colors.surfaceElevated)
                .cornerRadius(16)
        }
    }

    // MARK: - Helpers

    private func daysRemaining(_ endDate: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        if days < 0 { return "Ended" }
        if days == 0 { return "Ends today" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }

    private func dateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

// MARK: - Color for Challenge Type

func colorForType(_ type: ChallengeType) -> Color {
    switch type {
    case .volume: return Theme.Colors.accentBlue
    case .consistency: return Theme.Colors.accentGreen
    case .pr: return Color(hex: "FFD700") // Gold
    }
}

#Preview {
    NavigationStack {
        ChallengesView()
    }
    .preferredColorScheme(.dark)
}
