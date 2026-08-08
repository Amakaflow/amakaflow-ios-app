//
//  FriendsListView.swift
//  AmakaFlow
//
//  AMA-2389: Settings → Friends — list / add / requests entry.
//

import SwiftUI

struct FriendsListView: View {
    @ObservedObject var store: FriendsSharingStore
    @State private var showAdd = false
    @State private var showInbox = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.acceptedFriends.isEmpty && store.incomingRequests.isEmpty && store.outgoingRequests.isEmpty {
                    teachEmpty
                } else {
                    if store.unhandledShareCount > 0 {
                        inboxTeaser
                    }
                    ForEach(store.acceptedFriends) { friendship in
                        friendRow(friendship)
                    }
                    Text("SWIPE A FRIEND TO REMOVE — THEY AREN'T NOTIFIED")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
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
        .accessibilityIdentifier("af_friends_list")
        .task { await store.reload() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                FriendsAddView(store: store)
            }
            .presentationDetents(friendsSheetDetents)
            .presentationDragIndicator(.visible)
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
                FriendsWaitingBadge(badgeValue: store.unhandledShareCount, accessibilityId: "af_friends_inbox_badge")
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

    private func friendRow(_ friendship: Friendship) -> some View {
        HStack(spacing: 11) {
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
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { try? await store.remove(friendship) }
            } label: {
                Text("Remove")
            }
        }
        .accessibilityIdentifier("af_friends_row_\(friendship.peer.handleNormalized)")
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
