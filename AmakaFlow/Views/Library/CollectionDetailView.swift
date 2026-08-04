//
//  CollectionDetailView.swift
//  AmakaFlow
//
//  AMA-2376 Task 6: Collection detail + Organize mode (move / pin / remove).
//  Uncategorized (`CollectionPresentation.uncategorizedID`) reuses this same
//  screen — it just isn't a real DB row, so renaming/adding never apply to it
//  and Remove is a no-op for membership (it's already unfiled).
//

import SwiftUI

struct CollectionDetailView: View {
    let collectionID: String
    @ObservedObject var collectionsStore: LibraryCollectionsStore
    let workoutsByID: [String: Workout]
    let onOpenWorkout: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isOrganizing = false
    @State private var selectedIDs: Set<String> = []
    @State private var isPresentingMoveSheet = false
    @State private var isPresentingAddWorkouts = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(memberWorkouts) { workout in
                            CollectionMemberRow(
                                workout: workout,
                                isOrganizing: isOrganizing,
                                isSelected: selectedIDs.contains(workout.id),
                                isPinned: pinnedSet.contains(workout.id)
                            ) {
                                handleRowTap(workout.id)
                            }
                        }

                        if memberWorkouts.isEmpty {
                            Text("No workouts here yet.")
                                .font(.system(size: 12))
                                .foregroundColor(DailyDriver.foregroundMuted)
                                .padding(.vertical, 30)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, footerBottomPadding)
                }

                if !isOrganizing && canAddWorkouts {
                    addWorkoutsFooter
                }
            }

            if isOrganizing {
                organizeBar
            }

            if let toastMessage {
                toastView(toastMessage)
                    .padding(.horizontal, 18)
                    .padding(.bottom, isOrganizing ? 86 : 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $isPresentingMoveSheet) {
            MoveToCollectionSheet(
                destinations: moveDestinations,
                onMove: { targetID in moveSelection(to: targetID) },
                onCreateAndMove: { name in createCollectionAndMove(name: name) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(DailyDriver.backgroundElevated)
        }
        .sheet(isPresented: $isPresentingAddWorkouts) {
            LibraryWorkoutPickView(
                title: "Add to \(displayName)",
                workouts: addableWorkouts,
                onAdd: { ids in
                    for workoutID in ids {
                        try? collectionsStore.addMember(collectionId: collectionID, workoutId: workoutID)
                    }
                    isPresentingAddWorkouts = false
                },
                onCancel: { isPresentingAddWorkouts = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(DailyDriver.screenBackground)
        }
        .accessibilityIdentifier("af_collection_detail")
        // AMA-2376: without this, the global floating tab bar (ContentView)
        // renders on top of organizeBar / addWorkoutsFooter, which are also
        // bottom-pinned — same pattern as UnifiedWorkoutDetailView.
        .ddSuppressFloatingChrome()
    }
}

// MARK: - Derived data

private extension CollectionDetailView {
    var isUncategorized: Bool {
        collectionID == CollectionPresentation.uncategorizedID
    }

    var collectionRecord: LocalWorkoutCollection? {
        collectionsStore.collections.first { $0.id == collectionID }
    }

    var displayName: String {
        isUncategorized ? "Uncategorized" : (collectionRecord?.name ?? "Collection")
    }

    var memberIDs: [String] {
        if isUncategorized {
            return collectionsStore.uncategorizedWorkoutIds(workoutsByID: workoutsByID)
        }
        return (try? collectionsStore.memberWorkoutIds(collectionId: collectionID)) ?? []
    }

    var memberWorkouts: [Workout] {
        memberIDs.compactMap { workoutsByID[$0] }
    }

    var totalSeconds: Int {
        memberWorkouts.reduce(0) { $0 + $1.duration }
    }

    var pinnedSet: Set<String> {
        Set(collectionsStore.pinnedIDs)
    }

    /// Uncategorized isn't a real collection row — you can't add a membership
    /// into it (there's nothing to insert a foreign key against).
    var canAddWorkouts: Bool {
        !isUncategorized
    }

    var addableWorkouts: [Workout] {
        let memberSet = Set(memberIDs)
        return workoutsByID.values
            .filter { !memberSet.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var moveDestinations: [MoveToCollectionSheet.Destination] {
        collectionsStore.gridModels(workoutsByID: workoutsByID)
            .filter { !$0.isUncategorized && $0.id != collectionID }
            .map { item in
                MoveToCollectionSheet.Destination(
                    id: item.id,
                    name: item.name,
                    workoutCount: item.workoutIDs.count,
                    previewWorkout: item.workoutIDs.first.flatMap { workoutsByID[$0] }
                )
            }
    }

    var footerBottomPadding: CGFloat {
        if isOrganizing { return 100 }
        return canAddWorkouts ? 70 : 30
    }
}

// MARK: - Header

private extension CollectionDetailView {
    var header: some View {
        VStack(spacing: 6) {
            HStack {
                backButton
                Spacer(minLength: 0)
                organizeToggle
            }

            Text(displayName)
                .ddDisplayText(21, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .lineLimit(1)

            metaLine
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Library")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(DailyDriver.foregroundMuted)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_collection_back")
    }

    @ViewBuilder
    var organizeToggle: some View {
        if isOrganizing {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isOrganizing = false }
                selectedIDs.removeAll()
            } label: {
                Text("Done")
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_collection_done")
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isOrganizing = true }
            } label: {
                Text("Organize")
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DailyDriver.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_collection_organize")
        }
    }

    @ViewBuilder
    var metaLine: some View {
        if isOrganizing {
            Button {
                selectedIDs.removeAll()
            } label: {
                Text(CollectionPresentation.organizeHeader(selectedCount: selectedIDs.count))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_organize_selected")
        } else {
            Text(
                CollectionPresentation.detailMeta(
                    workoutCount: memberIDs.count,
                    totalSeconds: totalSeconds,
                    note: isUncategorized ? nil : collectionRecord?.note
                )
            )
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.3)
            .foregroundColor(DailyDriver.foregroundMuted)
        }
    }
}

// MARK: - Footer / bottom bar

private extension CollectionDetailView {
    var addWorkoutsFooter: some View {
        Button {
            isPresentingAddWorkouts = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("Add workouts")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(DailyDriver.lime)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(DailyDriver.screenBackground)
        .overlay(Rectangle().fill(DailyDriver.border).frame(height: 1), alignment: .top)
        .accessibilityIdentifier("af_collection_add_workouts")
    }

    var organizeBar: some View {
        HStack(spacing: 0) {
            organizeBarButton(icon: "folder", title: "Move to", color: DailyDriver.foreground) {
                isPresentingMoveSheet = true
            }
            .accessibilityIdentifier("af_organize_move")

            organizeBarButton(icon: "pin", title: "Pin", color: DailyDriver.foreground) {
                togglePinForSelection()
            }
            .accessibilityIdentifier("af_organize_pin")

            organizeBarButton(icon: "xmark.circle", title: "Remove", color: DailyDriver.coral) {
                removeSelection()
            }
            .accessibilityIdentifier("af_organize_remove")
        }
        .padding(.top, 10)
        .padding(.bottom, 22)
        .background(DailyDriver.backgroundElevated)
        .overlay(Rectangle().fill(DailyDriver.border).frame(height: 1), alignment: .top)
    }

    func organizeBarButton(
        icon: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(selectedIDs.isEmpty)
        .opacity(selectedIDs.isEmpty ? 0.4 : 1)
    }
}

// MARK: - Toast

private extension CollectionDetailView {
    func toastView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DailyDriver.lime)
            Text(message)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(DailyDriver.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.backgroundElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("af_collection_toast")
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toastMessage = message }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { toastMessage = nil }
        }
    }
}

// MARK: - Actions

private extension CollectionDetailView {
    func handleRowTap(_ workoutID: String) {
        if isOrganizing {
            if selectedIDs.contains(workoutID) {
                selectedIDs.remove(workoutID)
            } else {
                selectedIDs.insert(workoutID)
            }
        } else {
            onOpenWorkout(workoutID)
        }
    }

    func moveSelection(to targetID: String) {
        // Preserve source collection / displayed order — Set iteration is unstable.
        let ids = memberWorkouts.map(\.id).filter(selectedIDs.contains)
        guard !ids.isEmpty else { return }
        try? collectionsStore.moveMembers(
            workoutIds: ids,
            fromCollectionId: collectionID,
            toCollectionId: targetID
        )
        selectedIDs.removeAll()
    }

    func createCollectionAndMove(name: String) {
        guard let created = try? collectionsStore.createCollection(name: name, note: nil) else { return }
        moveSelection(to: created.id)
    }

    func togglePinForSelection() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        let allPinned = ids.allSatisfy { pinnedSet.contains($0) }
        for workoutID in ids {
            try? collectionsStore.setPinned(workoutId: workoutID, isPinned: !allPinned)
        }
    }

    /// Uncategorized has no real membership row to drop — Remove is a no-op there
    /// (the workout is already unfiled), so no toast fires and selection just clears.
    func removeSelection() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        guard !isUncategorized else {
            selectedIDs.removeAll()
            return
        }
        for workoutID in ids {
            try? collectionsStore.removeMember(collectionId: collectionID, workoutId: workoutID)
        }
        showToast(CollectionPresentation.removedFromCollectionToast(collectionName: displayName))
        selectedIDs.removeAll()
    }
}
