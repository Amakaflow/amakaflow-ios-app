//
//  CreateWorkoutSheet.swift
//  AmakaFlow
//
//  Daily Driver "Add workout" sheet — explicit doors into import / create flows.
//

import SwiftUI

enum CreateWorkoutDoor: Equatable {
    case createWithAI
    case importURL
    case screenshot
    case speak
    case manual
    /// AMA-2389: receive shared workouts from friends.
    case fromFriends
    /// AMA-2426: notepad — already trained, log set by set.
    case logSession
}

struct CreateWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var friendsStore = FriendsSharingStore.shared
    var onSelect: (CreateWorkoutDoor) -> Void

    var body: some View {
        DDBottomSheetChrome(title: "Add workout") {
            VStack(spacing: 10) {
                DDDoorRow(
                    icon: "sparkles",
                    iconBackground: DailyDriver.lime,
                    iconForeground: DailyDriver.ink,
                    title: "Create with AI",
                    subtitle: "Describe it — the coach drafts it"
                ) {
                    dismissThen { onSelect(.createWithAI) }
                }
                .accessibilityIdentifier("create_door_ai")

                DDDoorRow(
                    icon: "link",
                    iconBackground: DailyDriver.lime,
                    iconForeground: DailyDriver.ink,
                    title: "Import from URL",
                    subtitle: "Instagram, TikTok, or YouTube"
                ) {
                    dismissThen { onSelect(.importURL) }
                }
                .accessibilityIdentifier("create_door_url")

                DDDoorRow(
                    icon: "camera.fill",
                    iconBackground: DailyDriver.purple,
                    title: "Screenshot",
                    subtitle: "Photo of a workout → draft"
                ) {
                    dismissThen { onSelect(.screenshot) }
                }
                .accessibilityIdentifier("create_door_screenshot")

                DDDoorRow(
                    icon: "square.and.pencil",
                    iconBackground: DailyDriver.card2,
                    title: "Build from scratch",
                    subtitle: "From scratch, exercise by exercise"
                ) {
                    dismissThen { onSelect(.manual) }
                }
                .accessibilityIdentifier("create_door_manual")

                // AMA-2426: after Build from scratch — ONE new row.
                DDDoorRow(
                    icon: "book.closed.fill",
                    iconBackground: DailyDriver.lime,
                    iconForeground: DailyDriver.ink,
                    title: LogbookCopy.logSessionTitle,
                    subtitle: LogbookCopy.logSessionSubtitle
                ) {
                    dismissThen { onSelect(.logSession) }
                } trailing: {
                    Text(LogbookCopy.newBadge)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(DailyDriver.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(DailyDriver.lime)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .accessibilityIdentifier(LogbookCopy.logSessionAccessibilityID)

                // AMA-2389: after Build from scratch (placement table).
                DDDoorRow(
                    icon: "person.2.fill",
                    iconBackground: DailyDriver.blue,
                    title: "From friends",
                    subtitle: FriendsCopy.fromFriendsSubtitle(names: friendsStore.senderNamesForBadge)
                ) {
                    dismissThen { onSelect(.fromFriends) }
                } trailing: {
                    FriendsWaitingBadge(
                        badgeValue: friendsStore.unhandledShareCount,
                        accessibilityId: "af_add_from_friends_badge"
                    )
                }
                .accessibilityIdentifier("af_add_from_friends")

                speakComingSoonFooter
            }
        }
        .accessibilityIdentifier("create_workout_sheet")
        .task { await friendsStore.reload() }
    }

    private var speakComingSoonFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Speak it — coming soon")
                .font(Theme.Typography.caption)
        }
        .foregroundColor(DailyDriver.foregroundMuted)
        .opacity(0.5)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Speak it, coming soon")
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            action()
        }
    }
}

#if DEBUG
#Preview {
    CreateWorkoutSheet { _ in }
}
#endif
