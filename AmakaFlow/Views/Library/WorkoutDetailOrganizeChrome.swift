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
    @State private var isPresentingFriendShare = false
    @State private var completions: [WorkoutCompletion] = []
    @State private var didLoadCompletions = false
    /// Gate chips until the first store reload finishes so Suggest/Social
    /// preview paths (fresh `LibraryCollectionsStore`) don't flash empty chips.
    @State private var didLoadCollections = false
    @State private var writeFailureMessage: String?
    @ObservedObject private var friendsStore = FriendsSharingStore.shared

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

            if didLoadCollections {
                chipsRow
                    .padding(.top, 12)
            }

            if let lastDoneLine {
                lastDoneRow(lastDoneLine)
                    .padding(.top, 10)
            }
        }
        .task {
            try? collectionsStore.reload()
            didLoadCollections = true
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
        .sheet(isPresented: $isPresentingFriendShare) {
            WorkoutFriendShareSheet(workout: workout, store: friendsStore)
                .presentationDetents(friendsSheetDetents)
                .presentationDragIndicator(.visible)
                .presentationBackground(DailyDriver.backgroundElevated)
        }
        .alert(
            "Couldn't update collections",
            isPresented: Binding(
                get: { writeFailureMessage != nil },
                set: { if !$0 { writeFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { writeFailureMessage = nil }
        } message: {
            Text(writeFailureMessage ?? "")
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
                tileLabel(
                    icon: "square.stack.fill",
                    title: "Collect",
                    isActive: !memberCollections.isEmpty
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_detail_collect")

            Button {
                onToWatch()
            } label: {
                tileLabel(icon: "tv", title: "To watch", isActive: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_detail_towatch")

            shareTile
        }
        .accessibilityIdentifier("af_detail_actions")
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

    /// AMA-2389: Share opens friend-send + system share sheet (existing tile).
    var shareTile: some View {
        Button {
            isPresentingFriendShare = true
        } label: {
            tileLabel(icon: "square.and.arrow.up", title: "Share", isActive: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_detail_share")
    }
}

// MARK: - Collection chips

private extension WorkoutDetailOrganizeChrome {
    @ViewBuilder
    var chipsRow: some View {
        // AMA-2395: membership chips only — Collect is the one collections door
        // (＋ Add removed). Row absent when the workout is in no collections.
        if !memberCollections.isEmpty {
            HStack(alignment: .center, spacing: 8) {
                Text("IN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                FlowLayout(spacing: 8) {
                    ForEach(memberCollections) { collection in
                        chip(for: collection)
                    }
                }
            }
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
            .accessibilityLabel("Remove")
            .accessibilityIdentifier("af_detail_collection_chip_\(collection.id)_remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DailyDriver.card2)
        .clipShape(Capsule(style: .continuous))
        // Prefer stable collection id — names are not unique after sanitize.
        .accessibilityIdentifier("af_detail_collection_chip_\(collection.id)")
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
        let pageSize = 50
        var offset = 0
        var gathered: [WorkoutCompletion] = []
        // Paginate until this workout appears or pages are exhausted (LAST DONE
        // must not hide when the matching completion falls past the first page).
        while offset < 500 {
            let page: [WorkoutCompletion]
            do {
                page = try await apiService.fetchCompletions(limit: pageSize, offset: offset)
            } catch {
                break
            }
            gathered.append(contentsOf: page)
            if page.contains(where: { $0.workoutId == workout.id }) || page.count < pageSize {
                break
            }
            offset += pageSize
        }
        completions = gathered
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
        do {
            try collectionsStore.setPinned(workoutId: workout.id, isPinned: !isPinned)
        } catch {
            reportWriteFailure()
        }
    }

    func toggleMembership(collectionId: String, isMember: Bool) {
        do {
            if isMember {
                try collectionsStore.addMember(collectionId: collectionId, workoutId: workout.id)
            } else {
                try collectionsStore.removeMember(collectionId: collectionId, workoutId: workout.id)
            }
        } catch {
            reportWriteFailure()
        }
    }

    func removeMembership(collectionId: String) {
        do {
            try collectionsStore.removeMember(collectionId: collectionId, workoutId: workout.id)
        } catch {
            reportWriteFailure()
        }
    }

    func createCollectionAndAdd(name: String) {
        do {
            let created = try collectionsStore.createCollection(name: name, note: nil)
            try collectionsStore.addMember(collectionId: created.id, workoutId: workout.id)
        } catch {
            writeFailureMessage = "Couldn't create collection — try again"
        }
    }

    func reportWriteFailure(_ message: String = "Couldn't update collections — try again") {
        writeFailureMessage = message
    }
}
