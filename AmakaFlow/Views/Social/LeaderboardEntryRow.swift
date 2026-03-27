//
//  LeaderboardEntryRow.swift
//  AmakaFlow
//
//  Single row in a leaderboard — rank medal for top 3, avatar, name, value (AMA-1278)
//

import SwiftUI

struct LeaderboardEntryRow: View {
    let entry: LeaderboardEntryModel
    let formattedValue: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Rank
            rankBadge

            // Avatar placeholder
            Circle()
                .fill(entry.isMe ? Theme.Colors.accentBlue.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(entry.displayName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(entry.isMe ? Theme.Colors.accentBlue : .gray)
                )

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isMe ? "You" : entry.displayName)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                if entry.isMe {
                    Text("That's you!")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }

            Spacer()

            // Value
            Text(formattedValue)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(entry.isMe ? Theme.Colors.accentBlue : Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            entry.isMe
                ? Theme.Colors.accentBlue.opacity(0.08)
                : Color.clear
        )
        .cornerRadius(12)
    }

    // MARK: - Rank Badge

    @ViewBuilder
    private var rankBadge: some View {
        switch entry.rank {
        case 1:
            medalView(emoji: "🥇", color: Color(hex: "FFD700"))
        case 2:
            medalView(emoji: "🥈", color: Color(hex: "C0C0C0"))
        case 3:
            medalView(emoji: "🥉", color: Color(hex: "CD7F32"))
        default:
            Text("\(entry.rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 32, height: 32)
        }
    }

    private func medalView(emoji: String, color: Color) -> some View {
        Text(emoji)
            .font(.system(size: 22))
            .frame(width: 32, height: 32)
    }
}
