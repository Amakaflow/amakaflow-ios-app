//
//  FriendsUIComponents.swift
//  AmakaFlow
//
//  AMA-2389: Shared friends UI atoms (privacy note, avatar, waiting badge).
//

import SwiftUI

struct FriendsPrivacyNote: View {
    var text: String = FriendsCopy.privacyContractMono

    var body: some View {
        Text(text)
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

struct FriendRemoveConfirmPanel: View {
    let displayName: String
    let a11yHandle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(FriendsCopy.removeConfirm(displayName: displayName))
                .font(.system(size: 12))
                .foregroundColor(DailyDriver.foreground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    Text("Remove")
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(DailyDriver.destructive)
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_friends_remove_confirm_\(a11yHandle)")

                Button(action: onCancel) {
                    Text("Cancel")
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(DailyDriver.card2)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(DailyDriver.borderStrong, lineWidth: 1)
                        )
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(DailyDriver.destructive.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DailyDriver.destructive.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// AMA-2389: Profile hub Friends entry row (under week dots).
struct ProfileFriendsEntryRow: View {
    let friendCount: Int
    let waitingCount: Int
    var requestCount: Int = 0
    let onTap: () -> Void

    private var badgeValue: Int { requestCount + waitingCount }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                DDIconChip(
                    systemName: "person.2.fill",
                    background: DailyDriver.purple,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friends")
                        .ddDisplayText(15, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(
                        FriendsCopy.profileEntrySubtitle(
                            friendCount: friendCount,
                            waitingCount: waitingCount,
                            requestCount: requestCount
                        )
                    )
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                FriendsWaitingBadge(
                    badgeValue: badgeValue,
                    accessibilityId: "af_profile_friends_badge"
                )
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_profile_friends_row")
    }
}
