//
//  FriendsListView.swift
//  AmakaFlow
//
//  AMA-2389: Profile → Friends — manage list / add / remove (silent).
//

import SwiftUI

struct FriendsListView: View {
    @ObservedObject var store: FriendsSharingStore
    @State private var isEditing = false
    @State private var pendingRemoveId: String?
    @State private var showInbox = false
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.acceptedFriends.isEmpty
                    && store.incomingRequests.isEmpty
                    && store.outgoingRequests.isEmpty {
                    teachEmpty
                } else {
                    if store.unhandledShareCount >= 1 {
                        inboxTeaser
                    }
                    ForEach(store.acceptedFriends) { friendship in
                        friendManageCard(friendship)
                    }
                    FriendsPrivacyNote(text: FriendsCopy.privacyRemovingSilentMono)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Mockup: Edit/Done pill + green + on the trailing edge (back is system "< Profile").
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    if !store.acceptedFriends.isEmpty {
                        Button(isEditing ? "Done" : "Edit") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing.toggle()
                                if !isEditing { pendingRemoveId = nil }
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isEditing ? DailyDriver.ink : DailyDriver.foreground)
                        .padding(.horizontal, isEditing ? 12 : 10)
                        .padding(.vertical, 6)
                        .background(isEditing ? DailyDriver.foreground : Color.clear)
                        .clipShape(Capsule(style: .continuous))
                        .accessibilityIdentifier(isEditing ? "af_friends_done" : "af_friends_edit")
                    }

                    Button {
                        isEditing = false
                        pendingRemoveId = nil
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DailyDriver.lime)
                            .frame(width: 34, height: 34)
                            .background(DailyDriver.card2)
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("af_friends_add")
                }
            }
        }
        .accessibilityIdentifier("af_friends_list")
        .task { await store.reload() }
        .navigationDestination(isPresented: $showAdd) {
            FriendsAddView(store: store)
        }
        .sheet(isPresented: $showInbox) {
            NavigationStack {
                FriendsInboxView(store: store)
            }
            .presentationDetents(friendsSheetDetents)
            .presentationDragIndicator(.visible)
        }
    }

    private var teachEmpty: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            HStack(spacing: -10) {
                FriendAvatarChip(name: "D A", accent: DailyDriver.lime, size: 42)
                FriendAvatarChip(name: "M O", accent: DailyDriver.blue, size: 42)
                FriendAvatarChip(name: "P S", accent: DailyDriver.purple, size: 42)
            }
            Text(FriendsCopy.teachHeadline)
                .ddDisplayText(22, weight: .heavy)
                .multilineTextAlignment(.center)
            Text(FriendsCopy.teachBody)
                .font(.system(size: 12))
                .foregroundColor(DailyDriver.foregroundMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Button {
                showAdd = true
            } label: {
                Text("Add a friend")
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            FriendsPrivacyNote()
            Spacer(minLength: 40)
        }
    }

    private var inboxTeaser: some View {
        Button {
            showInbox = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "tray.fill")
                    .foregroundColor(DailyDriver.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text("From your people")
                        .ddDisplayText(13, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text("\(store.unhandledShareCount) WORKOUTS WAITING · \(store.senderNamesForBadge.joined(separator: ", ").uppercased())")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                Spacer(minLength: 0)
                FriendsWaitingBadge(
                    badgeValue: store.unhandledShareCount,
                    accessibilityId: "af_friends_inbox_badge"
                )
            }
            .padding(13)
            .background(DailyDriver.lime.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DailyDriver.lime.opacity(0.40), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_friends_inbox_teaser")
    }

    @ViewBuilder
    private func friendManageCard(_ friendship: Friendship) -> some View {
        let isPendingRemove = pendingRemoveId == friendship.id
        let a11yHandle = FriendsCopy.a11yHandleToken(friendship.peer.handleNormalized)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 11) {
                if isEditing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            pendingRemoveId = isPendingRemove ? nil : friendship.id
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DailyDriver.destructive)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Remove \(friendship.peer.displayName)")
                    .accessibilityIdentifier("af_friends_remove_toggle_\(a11yHandle)")
                }

                FriendAvatarChip(
                    name: friendship.peer.displayName,
                    accent: friendAccentColor(friendship.peer.accentRaw)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(friendship.peer.displayName)
                        .ddDisplayText(13.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text("@\(friendship.peer.handleNormalized)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                    Text(FriendsCopy.friendRowMeta(createdAt: friendship.createdAt))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)

            if isPendingRemove {
                VStack(alignment: .leading, spacing: 10) {
                    Text(FriendsCopy.removeConfirm(displayName: friendship.peer.displayName))
                        .font(.system(size: 12))
                        .foregroundColor(DailyDriver.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                try? await store.remove(friendship)
                                pendingRemoveId = nil
                                if store.acceptedFriends.isEmpty {
                                    isEditing = false
                                }
                            }
                        } label: {
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

                        Button {
                            withAnimation { pendingRemoveId = nil }
                        } label: {
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
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isPendingRemove ? DailyDriver.destructive.opacity(0.55) : DailyDriver.border,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Keep children (edit/− buttons) queryable by Maestro — don't collapse the card.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("af_friends_row_\(a11yHandle)")
    }
}

/// UITEST / iOS 26.1 medium-detent a11y gap — prefer large when any UITEST_* is set.
var friendsSheetDetents: Set<PresentationDetent> {
    #if DEBUG
    if UITestEnvironment.isTruthy("UITEST_USE_FIXTURES")
        || UITestEnvironment.isTruthy("UITEST_SKIP_ONBOARDING") {
        return [.large, .medium]
    }
    #endif
    return [.medium, .large]
}
