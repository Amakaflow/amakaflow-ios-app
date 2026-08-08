//
//  ReceivedShareDetailView.swift
//  AmakaFlow
//
//  AMA-2389: Read-only structure preview + Save to Library + dedupe card.
//

import SwiftUI

struct ReceivedShareDetailView: View {
    let share: WorkoutShare
    @ObservedObject var store: FriendsSharingStore
    let library: [Workout]
    /// False when library fetch failed — block saves that depend on dedupe.
    var libraryReady: Bool = true
    var onSaved: () -> Void
    var onOpenExisting: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let api: APIServiceProviding

    init(
        share: WorkoutShare,
        store: FriendsSharingStore,
        library: [Workout],
        libraryReady: Bool = true,
        onSaved: @escaping () -> Void,
        onOpenExisting: @escaping (String) -> Void,
        api: APIServiceProviding = AppDependencies.current.apiService
    ) {
        self.share = share
        self.store = store
        self.library = library
        self.libraryReady = libraryReady
        self.onSaved = onSaved
        self.onOpenExisting = onOpenExisting
        self.api = api
    }

    private var dedupe: WorkoutShareDedupeMatch {
        store.dedupeMatch(for: share, library: library)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if case .strong = dedupe {
                    dedupeCard
                }
                structurePreview
                Text(FriendsCopy.saveSnapshotRule.uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .lineSpacing(3)
                saveButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .navigationTitle("From \(firstName(share.fromDisplayName))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            do {
                try await store.markSeen(share)
            } catch {
                // Non-fatal: badge may stay until next successful open/reload.
                errorMessage = error.localizedDescription
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(share.snapshot.name)
                .ddDisplayText(22, weight: .heavy)
            if let note = share.note, !note.isEmpty {
                Text("“\(note)”")
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            Text(FriendsCopy.attribution(fromName: share.fromDisplayName))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DailyDriver.lime)
        }
    }

    private var dedupeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You already have this one")
                .ddDisplayText(14, weight: .bold)
                .foregroundColor(DailyDriver.ink)
            if case .strong(_, let title) = dedupe {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(DailyDriver.ink.opacity(0.75))
            }
            HStack(spacing: 8) {
                Button {
                    if case .strong(let id, _) = dedupe {
                        onOpenExisting(id)
                        dismiss()
                    }
                } label: {
                    Text("Open yours ›")
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_recv_dup_open")

                Button {
                    Task { await save(copyAnyway: true) }
                } label: {
                    Text(isSaving ? "Saving…" : "Save copy anyway")
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(DailyDriver.amber.opacity(0.35))
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving || !libraryReady)
                .accessibilityIdentifier("af_recv_dup_copy")
            }
            Button {
                Task { await dismissShare() }
            } label: {
                Text("Not for me")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DailyDriver.ink.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(14)
        .background(DailyDriver.amber)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("af_recv_dup_card")
    }

    private var structurePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STRUCTURE")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)
            ForEach(Array(share.snapshot.intervals.enumerated()), id: \.offset) { index, interval in
                HStack(spacing: 11) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(interval.name ?? interval.type.capitalized)
                            .ddDisplayText(14, weight: .bold)
                        Text(intervalMeta(interval))
                            .font(.system(size: 11))
                            .foregroundColor(DailyDriver.foregroundMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(DailyDriver.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var saveButton: some View {
        Button {
            // When a strong match exists the amber card owns the decision —
            // never silently save a duplicate from this CTA.
            guard dedupe == .none else { return }
            Task { await save(copyAnyway: false) }
        } label: {
            Text(isSaving ? "Saving…" : "Save to Library")
                .ddDisplayText(14, weight: .bold)
                .foregroundColor(DailyDriver.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DailyDriver.lime)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || dedupe != .none || !libraryReady)
        .opacity(dedupe != .none || !libraryReady ? 0.45 : 1)
        .accessibilityIdentifier("af_recv_save")
    }

    private func save(copyAnyway: Bool) async {
        guard !isSaving else { return }
        guard libraryReady else {
            errorMessage = "Couldn't load your library — retry from the inbox."
            return
        }
        isSaving = true
        defer { isSaving = false }
        let toastId = DDToastCenter.shared.beginPending(text: "Saving…")
        do {
            let title: String?
            if copyAnyway {
                title = share.snapshot.name + FriendsCopy.copySuffix(fromName: share.fromDisplayName)
            } else {
                title = nil
            }
            _ = try await store.saveShare(share, titleOverride: title, api: api)
            DDToastCenter.shared.resolve(
                id: toastId,
                kind: .success,
                text: "Saved to Library",
                sub: FriendsCopy.attribution(fromName: share.fromDisplayName)
            )
            NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)
            onSaved()
            dismiss()
        } catch {
            DDToastCenter.shared.resolve(
                id: toastId,
                kind: .error,
                text: "Couldn't save",
                sub: error.localizedDescription
            )
            errorMessage = error.localizedDescription
        }
    }

    private func dismissShare() async {
        do {
            try await store.dismissShare(share)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func intervalMeta(_ interval: WorkoutSaveInterval) -> String {
        if let sets = interval.sets, let reps = interval.reps {
            return "\(sets) × \(reps)"
        }
        if let seconds = interval.seconds {
            return "\(seconds)s"
        }
        if let meters = interval.meters {
            return "\(meters)m"
        }
        return interval.type
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}
