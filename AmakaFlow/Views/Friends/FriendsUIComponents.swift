//
//  FriendsUIComponents.swift
//  AmakaFlow
//
//  AMA-2389: Shared friends UI atoms (privacy note, avatar, waiting badge).
//

import SwiftUI

struct FriendsPrivacyNote: View {
    var body: some View {
        Text(FriendsCopy.privacyContractMono)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundDim)
            .lineSpacing(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(DailyDriver.border)
            )
            .accessibilityIdentifier("af_friends_privacy_note")
    }
}

struct FriendAvatarChip: View {
    let name: String
    var accent: Color = DailyDriver.blue
    var size: CGFloat = 34

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .heavy))
            .foregroundColor(accent)
            .frame(width: size, height: size)
            .background(accent.opacity(0.28))
            .clipShape(Circle())
    }

    private var initials: String {
        let parts = name.split(separator: " ").map(String.init)
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

struct FriendsWaitingBadge: View {
    let badgeValue: Int
    var accessibilityId: String

    var body: some View {
        if badgeValue >= 1 {
            Text("\(badgeValue)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(DailyDriver.ink)
                .padding(.horizontal, 7)
                .frame(minWidth: 20, minHeight: 20)
                .background(DailyDriver.lime)
                .clipShape(Capsule(style: .continuous))
                .accessibilityIdentifier(accessibilityId)
        }
    }
}

func friendAccentColor(_ raw: String) -> Color {
    switch raw.lowercased() {
    case "purple": return DailyDriver.purple
    case "amber": return DailyDriver.amber
    case "lime": return DailyDriver.lime
    default: return DailyDriver.blue
    }
}
