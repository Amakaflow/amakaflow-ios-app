//
//  WorkoutDetailOrganizeChrome.swift
//  AmakaFlow
//
//  AMA-2376 Task 7: UnifiedWorkoutDetailView organize chrome — split out of
//  the main file (already SwiftLint file_length-flagged). Renders the
//  Pin / Collect / To watch / Share action row, collection membership chips
//  (with an inline "+ Add" affordance), and the honest LAST DONE row.
//

import SwiftUI

struct WorkoutDetailOrganizeChrome: View {
    let workout: Workout
    @ObservedObject var collectionsStore: LibraryCollectionsStore
    /// AMA-2376: "To watch" reuses the exact Start handoff (importContext-aware,
    /// no crash on block) — the parent owns `startFlowSheet` state.
    let onToWatch: () -> Void

    private let apiService: APIServiceProviding

    @State private var isPresentingAddToCollection = false
    @State private var completions: [WorkoutCompletion] = []
    @State private var didLoadCompletions = false

    init(
        workout: Workout,
        collectionsStore: LibraryCollectionsStore,
        onToWatch: @escaping () -> Void,
        apiService: APIServiceProviding = AppDependencies.current.apiService
    ) {
        self.workout = workout
        _collectionsStore = ObservedObject(wrappedValue: collectionsStore)
        self.onToWatch = onToWatch
        self.apiService = apiService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow

            chipsRow
                .padding(.top, 12)

            if let lastDoneLine {
                lastDoneRow(lastDoneLine)
                    .padding(.top, 10)
            }
        }
        .task {
            try? collectionsStore.reload()
            await loadCompletionsIfNeeded()
        }
        .sheet(isPresented: $isPresentingAddToCollection) {
            AddToCollectionSheet(
                items: collectionItems,
                memberIDs: memberIDs,
                onToggle: toggleMembership,
                onCreateAndAdd: createCollectionAndAdd
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(DailyDriver.backgroundElevated)
        }
    }
}

// MARK: - Action row

private extension WorkoutDetailOrganizeChrome {
    var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                togglePin()
            } label: {
                tileLabel(icon: isPinned ? "pin.fill" : "pin", title: "Pin", isActive: isPinned)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_detail_pin")

            Button {
                isPresentingAddToCollection = true
            } label: {
                tileLabel(icon: "square.stack.fill", title: "Collect", isActive: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_detail_collect")

            Button {
                onToWatch()
            } label: {
                tileLabel(icon: "tv", title: "To watch", isActive: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_detail_to_watch")

            shareTile
        }
    }

    func tileLabel(icon: String, title: String, isActive: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundColor(isActive ? DailyDriver.ink : DailyDriver.foreground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isActive ? DailyDriver.lime : DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? Color.clear : DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Honest Share: prefers the source URL, falls back to the workout name as
    /// plain text, and disables (no crash) only if the name itself is empty.
    @ViewBuilder
    var shareTile: some View {
        if let shareURL {
            ShareLink(item: shareURL, subject: Text(workout.name)) {
                tileLabel(icon: "square.and.arrow.up", title: "Share", isActive: false)
            }
            .accessibilityIdentifier("af_detail_share")
        } else if let shareText {
            ShareLink(item: shareText) {
                tileLabel(icon: "square.and.arrow.up", title: "Share", isActive: false)
            }
            .accessibilityIdentifier("af_detail_share")
        } else {
            tileLabel(icon: "square.and.arrow.up", title: "Share", isActive: false)
                .opacity(0.4)
                .accessibilityIdentifier("af_detail_share")
        }
    }

    var shareURL: URL? {
        guard let sourceUrl = workout.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceUrl.isEmpty,
              let url = URL(string: sourceUrl),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    var shareText: String? {
        let trimmed = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Collection chips

private extension WorkoutDetailOrganizeChrome {
    var chipsRow: some View {
        FlowLayout(spacing: 8) {
            ForEach(memberCollections) { collection in
                chip(for: collection)
            }
            addChip
        }
    }

    func chip(for collection: LocalWorkoutCollection) -> some View {
        HStack(spacing: 6) {
            Text(collection.name.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.3)
                .foregroundColor(DailyDriver.foreground)
                .lineLimit(1)

            Button {
                removeMembership(collectionId: collection.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_detail_collection_chip_\(collection.id)_remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DailyDriver.card2)
        .clipShape(Capsule(style: .continuous))
        .accessibilityIdentifier("af_detail_collection_chip_\(collection.id)")
    }

    var addChip: some View {
        Button {
            isPresentingAddToCollection = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("Add")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(DailyDriver.lime)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DailyDriver.lime.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_detail_collection_add_chip")
    }
}

// MARK: - LAST DONE

private extension WorkoutDetailOrganizeChrome {
    var lastDoneLine: String? {
        WorkoutLastDonePresentation.line(from: completions, workoutId: workout.id)
    }

    func lastDoneRow(_ line: String) -> some View {
        HStack(spacing: 8) {
            Text("LAST DONE")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundColor(DailyDriver.foregroundDim)
            Text(line)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundMuted)
        }
        .accessibilityIdentifier("af_detail_last_done")
    }

    func loadCompletionsIfNeeded() async {
        guard !didLoadCompletions else { return }
        didLoadCompletions = true
        completions = (try? await apiService.fetchCompletions(limit: 50, offset: 0)) ?? []
    }
}

// MARK: - Derived state + actions

private extension WorkoutDetailOrganizeChrome {
    var isPinned: Bool {
        collectionsStore.pinnedIDs.contains(workout.id)
    }

    var memberCollections: [LocalWorkoutCollection] {
        collectionsStore.collections(containing: workout.id)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var memberIDs: Set<String> {
        Set(memberCollections.map(\.id))
    }

    var collectionItems: [AddToCollectionSheet.Item] {
        collectionsStore.collections.map { collection in
            let count = (try? collectionsStore.memberWorkoutIds(collectionId: collection.id).count) ?? 0
            return AddToCollectionSheet.Item(id: collection.id, name: collection.name, workoutCount: count)
        }
    }

    func togglePin() {
        try? collectionsStore.setPinned(workoutId: workout.id, isPinned: !isPinned)
    }

    func toggleMembership(collectionId: String, isMember: Bool) {
        if isMember {
            try? collectionsStore.addMember(collectionId: collectionId, workoutId: workout.id)
        } else {
            try? collectionsStore.removeMember(collectionId: collectionId, workoutId: workout.id)
        }
    }

    func removeMembership(collectionId: String) {
        try? collectionsStore.removeMember(collectionId: collectionId, workoutId: workout.id)
    }

    func createCollectionAndAdd(name: String) {
        guard let created = try? collectionsStore.createCollection(name: name, note: nil) else { return }
        try? collectionsStore.addMember(collectionId: created.id, workoutId: workout.id)
    }
}
