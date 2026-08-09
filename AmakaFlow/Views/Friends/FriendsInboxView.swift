//
//  FriendsInboxView.swift
//  AmakaFlow
//
//  AMA-2389: From friends — review received shares.
//

import SwiftUI

struct FriendsInboxView: View {
    @ObservedObject var store: FriendsSharingStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedShare: WorkoutShare?
    @State private var library: [Workout] = []
    @State private var libraryLoadFailed = false
    @State private var actionError: String?

    private let api: APIServiceProviding

    init(
        store: FriendsSharingStore,
        api: APIServiceProviding = AppDependencies.current.apiService
    ) {
        self.store = store
        self.api = api
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if libraryLoadFailed {
                    libraryErrorBanner
                }
                if store.incomingShares.isEmpty {
                    Text("Nothing waiting — friends' workouts land here.")
                        .font(.system(size: 13))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.top, 40)
                } else {
                    ForEach(store.incomingShares) { share in
                        shareCard(share)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationTitle("From friends")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .task { await loadLibrary() }
        .sheet(item: $selectedShare) { share in
            NavigationStack {
                ReceivedShareDetailView(
                    share: share,
                    store: store,
                    library: library,
                    libraryReady: !libraryLoadFailed,
                    onSaved: { dismiss() },
                    onOpenExisting: { workoutId in
                        selectedShare = nil
                        dismiss()
                        NotificationCenter.default.post(
                            name: .libraryOpenWorkout,
                            object: nil,
                            userInfo: ["workoutId": workoutId]
                        )
                    }
                )
            }
            .presentationDetents(friendsSheetDetents)
        }
        .alert("Couldn't update", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var libraryErrorBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load your library")
                .ddDisplayText(13, weight: .bold)
            Text("Duplicate checks need your library. Retry before saving.")
                .font(.system(size: 12))
                .foregroundColor(DailyDriver.foregroundMuted)
            Button {
                Task { await loadLibrary() }
            } label: {
                Text("Retry")
                    .ddDisplayText(12, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_recv_library_retry")
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.amber.opacity(0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.amber.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func loadLibrary() async {
        await store.reload()
        do {
            library = try await api.fetchWorkouts()
            libraryLoadFailed = false
        } catch {
            library = []
            libraryLoadFailed = true
            actionError = error.localizedDescription
        }
    }

    private func shareCard(_ share: WorkoutShare) -> some View {
        let unread = share.isUnhandled
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                FriendAvatarChip(name: share.fromDisplayName, size: 26)
                Text("FROM \(firstName(share.fromDisplayName).uppercased()) · \(unread ? "NEW" : "SAVED ✓")")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(unread ? DailyDriver.lime : DailyDriver.foregroundDim)
                Spacer(minLength: 0)
            }
            Text(share.snapshot.name)
                .ddDisplayText(15, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 7)
            if let note = share.note, !note.isEmpty {
                Text("“\(note)”")
                    .font(.system(size: 11))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.top, 3)
            }
            Text(metaLine(share))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
                .padding(.top, 5)

            if unread {
                HStack(spacing: 8) {
                    Button {
                        selectedShare = share
                    } label: {
                        Text("Look inside")
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(DailyDriver.lime)
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_recv_look")

                    Button {
                        Task {
                            do {
                                try await store.dismissShare(share)
                            } catch {
                                actionError = error.localizedDescription
                            }
                        }
                    } label: {
                        Text("Not for me")
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.foreground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(DailyDriver.card2)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(DailyDriver.borderStrong, lineWidth: 1)
                            )
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_recv_dismiss_\(share.id)")
                }
                .padding(.top, 10)
            }
        }
        .padding(13)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    unread ? DailyDriver.lime.opacity(0.45) : DailyDriver.border,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(unread ? 1 : 0.72)
        .accessibilityIdentifier("af_recv_row_\(share.id)")
    }

    private func metaLine(_ share: WorkoutShare) -> String {
        let count = share.snapshot.intervals.count
        return "\(count) EXERCISES · SNAPSHOT COPY"
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}
