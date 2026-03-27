//
//  ChallengeDetailView.swift
//  AmakaFlow
//
//  Challenge detail — progress bar, leaderboard, participant list, join button (AMA-1276)
//

import SwiftUI

struct ChallengeDetailView: View {
    let challengeId: String
    @ObservedObject var viewModel: ChallengesViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingDetail && viewModel.selectedChallenge == nil {
                ProgressView("Loading challenge...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = viewModel.selectedChallenge {
                detailContent(detail)
            } else {
                Text("Challenge not found")
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadChallengeDetail(id: challengeId)
        }
        .overlay {
            if viewModel.showCelebration, let badge = viewModel.completedBadge {
                ChallengeCompletionView(badge: badge) {
                    viewModel.dismissCelebration()
                }
            }
        }
    }

    // MARK: - Detail Content

    private func detailContent(_ detail: ChallengeDetailResponse) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                challengeHeader(detail.challenge)

                if let progress = detail.myProgress {
                    progressSection(progress, challenge: detail.challenge)
                }

                if !detail.challenge.isJoined {
                    joinButton
                }

                if !detail.leaderboard.isEmpty {
                    leaderboardSection(detail.leaderboard)
                }
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    // MARK: - Challenge Header

    private func challengeHeader(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(challenge.title)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text(challenge.type.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(colorForType(challenge.type))
                    .cornerRadius(8)
            }

            if let description = challenge.description {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.lg) {
                infoItem(icon: "person.2.fill", value: "\(challenge.participantCount)", label: "Participants")
                infoItem(icon: "target", value: "\(Int(challenge.target)) \(challenge.targetUnit)", label: "Target")
                infoItem(icon: "calendar", value: daysRemaining(challenge.endDate), label: "Remaining")
            }
            .padding(.top, Theme.Spacing.xs)

            if challenge.isTeamMode {
                HStack(spacing: 6) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 12))
                    Text("Team Challenge")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Theme.Colors.accentBlue)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(12)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Progress Section

    private func progressSection(_ progress: ChallengeProgress, challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("My Progress")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Colors.surfaceElevated)
                    .frame(height: 32)

                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorForType(challenge.type))
                        .frame(width: geometry.size.width * min(progress.percentage / 100.0, 1.0), height: 32)
                }
                .frame(height: 32)

                Text("\(Int(progress.percentage))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.leading, 12)
            }
            .frame(height: 32)

            HStack {
                Text("\(formattedValue(progress.currentValue)) / \(formattedValue(progress.targetValue)) \(challenge.targetUnit)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer()

                if progress.isCompleted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Completed!")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.accentGreen)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(12)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Join Button

    private var joinButton: some View {
        Button {
            Task { await viewModel.joinChallenge(id: challengeId) }
        } label: {
            HStack {
                if viewModel.isJoining {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "flag.fill")
                    Text("Join Challenge")
                }
            }
            .font(Theme.Typography.bodyBold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.Colors.accentBlue)
            .cornerRadius(12)
        }
        .disabled(viewModel.isJoining)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Leaderboard

    private func leaderboardSection(_ entries: [LeaderboardEntry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Leaderboard")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)

            ForEach(entries) { entry in
                leaderboardRow(entry)
            }
        }
    }

    private func leaderboardRow(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("#\(entry.rank)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(rankColor(entry.rank))
                .frame(width: 36)

            Circle()
                .fill(Theme.Colors.surfaceElevated)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(entry.userName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

            Text(entry.userName)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(entry.progressPercentage))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)

                ProgressView(value: min(entry.progressPercentage / 100.0, 1.0))
                    .tint(colorForType(viewModel.selectedChallenge?.challenge.type ?? .volume))
                    .frame(width: 60)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Helpers

    private func infoItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: "FFD700")
        case 2: return Color(hex: "C0C0C0")
        case 3: return Color(hex: "CD7F32")
        default: return Theme.Colors.textSecondary
        }
    }

    private func daysRemaining(_ endDate: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        if days < 0 { return "Ended" }
        if days == 0 { return "Today" }
        if days == 1 { return "1 day" }
        return "\(days) days"
    }

    private func formattedValue(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack {
        ChallengeDetailView(challengeId: "preview-1", viewModel: ChallengesViewModel())
    }
    .preferredColorScheme(.dark)
}
