//
//  WorkoutFriendShareSheet.swift
//  AmakaFlow
//
//  AMA-2389: Share sheet — Send to a friend (top) + system share (below).
//  Builds into the existing Share tile; never invents a new surface.
//

import SwiftUI

struct WorkoutFriendShareSheet: View {
    let workout: Workout
    @ObservedObject var store: FriendsSharingStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFriendIds: Set<String> = []
    @State private var note: String = ""
    @State private var isSending = false

    private var selectedCount: Int { selectedFriendIds.count }
    private var canSend: Bool { selectedCount > 0 && !isSending }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 12)

            Text("Share")
                .ddDisplayText(19, weight: .heavy)
                .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SEND TO A FRIEND — LANDS IN THEIR ＋ · FROM FRIENDS")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 7)

                    summaryCard
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)

                    ForEach(store.acceptedFriends) { friendship in
                        friendSelectRow(friendship)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 6)
                    }

                    if store.acceptedFriends.isEmpty {
                        Text("Add friends in Settings to send workouts.")
                            .font(.system(size: 12))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                    }

                    TextField("Optional note", text: $note)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(DailyDriver.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 18)
                        .padding(.top, 6)

                    Text(FriendsCopy.snapshotHonesty.uppercased())
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineSpacing(3)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                }
            }

            Button {
                Task { await send() }
            } label: {
                Text(FriendsCopy.sendCTA(selectedFriendCount: selectedCount))
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(canSend ? DailyDriver.ink : DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canSend ? DailyDriver.lime : DailyDriver.card2)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .accessibilityIdentifier("af_share_send")

            systemShareRow
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 18)
        }
        .background(DailyDriver.backgroundElevated)
        .accessibilityIdentifier("af_share_sheet")
        .task { await store.reload() }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("FROM YOUR LIBRARY")
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
            Text(workout.name)
                .ddDisplayText(14.5, weight: .bold)
            HStack(spacing: 5) {
                metaPill("\(workout.intervals.count) EXERCISES")
                metaPill(workout.sport.rawValue.uppercased())
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DailyDriver.card2)
            .clipShape(Capsule(style: .continuous))
    }

    private func friendSelectRow(_ friendship: Friendship) -> some View {
        let isSelected = selectedFriendIds.contains(friendship.peer.id)
        return Button {
            if isSelected {
                selectedFriendIds.remove(friendship.peer.id)
            } else {
                selectedFriendIds.insert(friendship.peer.id)
            }
        } label: {
            HStack(spacing: 11) {
                FriendAvatarChip(
                    name: friendship.peer.displayName,
                    accent: friendAccentColor(friendship.peer.accentRaw),
                    size: 30
                )
                Text(friendship.peer.displayName)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .stroke(DailyDriver.borderStrong, lineWidth: 1.5)
                        .frame(width: 19, height: 19)
                    if isSelected {
                        Circle()
                            .fill(DailyDriver.lime)
                            .frame(width: 19, height: 19)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DailyDriver.ink)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        on ? DailyDriver.lime.opacity(0.55) : DailyDriver.border,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_share_friend_row_\(friendship.peer.handleNormalized)")
    }

    @ViewBuilder
    private var systemShareRow: some View {
        VStack(spacing: 0) {
            Divider().background(DailyDriver.border)
            if let shareURL {
                ShareLink(item: shareURL, subject: Text(workout.name)) {
                    systemShareLabel
                }
                .accessibilityIdentifier("af_share_system")
            } else if let shareText {
                ShareLink(item: shareText) {
                    systemShareLabel
                }
                .accessibilityIdentifier("af_share_system")
            } else {
                systemShareLabel
                    .opacity(0.4)
                    .accessibilityIdentifier("af_share_system")
            }
        }
    }

    private var systemShareLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(DailyDriver.foregroundMuted)
            Text("Share elsewhere — link, Messages…")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundMuted)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private var shareURL: URL? {
        guard let sourceUrl = workout.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceUrl.isEmpty,
              let url = URL(string: sourceUrl),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    private var shareText: String? {
        let trimmed = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func send() async {
        guard canSend else { return }
        isSending = true
        let toastId = DDToastCenter.shared.beginPending(text: "Sending…")
        do {
            let count = try await store.send(
                workout: workout,
                toFriendIds: Array(selectedFriendIds),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
            )
            DDToastCenter.shared.resolve(
                id: toastId,
                kind: .success,
                text: count == 1 ? "Sent to 1 friend" : "Sent to \(count) friends"
            )
            dismiss()
        } catch {
            DDToastCenter.shared.resolve(
                id: toastId,
                kind: .error,
                text: "Couldn't send",
                sub: error.localizedDescription
            )
        }
        isSending = false
    }
}
