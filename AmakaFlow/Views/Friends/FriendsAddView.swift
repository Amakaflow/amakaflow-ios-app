//
//  FriendsAddView.swift
//  AmakaFlow
//
//  AMA-2389: Add a friend — username search, invite link, requests.
//

import SwiftUI

struct FriendsAddView: View {
    @ObservedObject var store: FriendsSharingStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FriendProfile] = []
    @State private var toastNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                searchField
                ForEach(results) { profile in
                    searchResultRow(profile)
                }

                Text("NOT ON AMAKAFLOW YET?")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.top, 4)

                inviteLinkCard

                if !store.incomingRequests.isEmpty || !store.outgoingRequests.isEmpty {
                    Text("REQUESTS")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(.top, 4)
                    ForEach(store.incomingRequests) { request in
                        incomingRequestRow(request)
                    }
                    ForEach(store.outgoingRequests) { request in
                        outgoingRequestRow(request)
                    }
                }

                FriendsPrivacyNote()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationTitle("Add a friend")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .task { await store.reload() }
        .onChange(of: query) { _, newValue in
            Task {
                results = await store.searchUsers(query: newValue)
            }
        }
        .overlay(alignment: .bottom) {
            if let toastNote {
                Text(toastNote)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DailyDriver.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule(style: .continuous))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DailyDriver.foregroundDim)
            TextField("Search @handle", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13))
                .foregroundColor(DailyDriver.foreground)
                .accessibilityIdentifier("af_friends_search")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func searchResultRow(_ profile: FriendProfile) -> some View {
        HStack(spacing: 11) {
            FriendAvatarChip(name: profile.displayName, accent: friendAccentColor(profile.accentRaw))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .ddDisplayText(13.5, weight: .bold)
                Text("@\(profile.handleNormalized)")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            Spacer(minLength: 0)
            Button {
                Task {
                    do {
                        try await store.requestFriend(handle: profile.handle)
                        flash("Request sent — \(profile.displayName.split(separator: " ").first ?? "") has to accept")
                        results = await store.searchUsers(query: query)
                    } catch {
                        flash(error.localizedDescription)
                    }
                }
            } label: {
                Text("Request")
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_friends_request_\(profile.handleNormalized)")
        }
        .padding(13)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var inviteLinkCard: some View {
        let url = store.inviteURL()
        return ShareLink(item: url) {
            HStack(spacing: 11) {
                Image(systemName: "link")
                    .foregroundColor(DailyDriver.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share your invite link")
                        .ddDisplayText(12.5, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text("\(url.host?.uppercased() ?? "AMAKAFLOW.COM")\(url.path.uppercased()) · \(FriendsCopy.inviteLinkHint)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(13)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityIdentifier("af_friends_invite_link")
    }

    private func incomingRequestRow(_ request: Friendship) -> some View {
        HStack(spacing: 11) {
            FriendAvatarChip(name: request.peer.displayName, accent: friendAccentColor(request.peer.accentRaw))
            VStack(alignment: .leading, spacing: 2) {
                Text(request.peer.displayName)
                    .ddDisplayText(13, weight: .bold)
                Text("WANTS TO ADD YOU · @\(request.peer.handleNormalized)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.amber)
            }
            Spacer(minLength: 0)
            Button {
                Task {
                    try? await store.accept(request)
                    flash("\(request.peer.displayName.split(separator: " ").first ?? "") added — you can swap workouts now")
                }
            } label: {
                Text("Accept")
                    .ddDisplayText(11.5, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_friends_request_accept")

            Button {
                Task { try? await store.decline(request) }
            } label: {
                Text("Decline")
                    .ddDisplayText(11.5, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_friends_request_decline")
        }
        .padding(13)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func outgoingRequestRow(_ request: Friendship) -> some View {
        HStack(spacing: 11) {
            FriendAvatarChip(name: request.peer.displayName, accent: friendAccentColor(request.peer.accentRaw))
            VStack(alignment: .leading, spacing: 2) {
                Text(request.peer.displayName)
                    .ddDisplayText(13, weight: .bold)
                Text("YOU ASKED · PENDING")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            Spacer(minLength: 0)
            Button {
                Task { try? await store.cancel(request) }
            } label: {
                Text("Cancel")
                    .ddDisplayText(11.5, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_friends_request_cancel")
        }
        .padding(13)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(DailyDriver.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(0.8)
    }

    private func flash(_ message: String) {
        withAnimation { toastNote = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { toastNote = nil }
        }
    }
}
