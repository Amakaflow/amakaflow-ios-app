//
//  LibraryView+Collections.swift
//  AmakaFlow
//
//  AMA-2376: New Collection alert + pin helpers for Library.
//

import SwiftUI

extension LibraryView {
    var pinnedWorkouts: [Workout] {
        viewModel.collectionsStore.pinnedIDs.compactMap { viewModel.workoutsByID[$0] }
    }

    func unpinWorkout(_ workoutID: String) {
        do {
            try viewModel.collectionsStore.setPinned(workoutId: workoutID, isPinned: false)
        } catch {
            collectionsAlertMessage = "Couldn't unpin workout — try again"
        }
    }

    func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCollectionName = ""
        guard !name.isEmpty else { return }
        do {
            let created = try viewModel.collectionsStore.createCollection(name: name, note: nil)
            navigationPath.append(.collection(id: created.id))
        } catch {
            collectionsAlertMessage = "Couldn't create collection — try again"
        }
    }

    // MARK: - Navigation destinations (split from LibraryView for file_length)

    @ViewBuilder
    func libraryDestinationView(_ destination: LibraryDestination) -> some View {
        switch destination {
        case .unifiedWorkout(let workoutID):
            if let workout = viewModel.resolveWorkout(for: destination) {
                UnifiedWorkoutDetailView(
                    workout: workout,
                    collectionsStore: viewModel.collectionsStore,
                    onEditorDismiss: {
                        await viewModel.load()
                        return viewModel.workout(for: workoutID)
                            ?? viewModel.resolveWorkout(for: destination)
                    },
                    onDelete: {
                        guard let target = viewModel.deleteTarget(forWorkoutID: workoutID) else {
                            return false
                        }
                        return await viewModel.deleteEntry(target)
                    }
                )
            } else {
                Text("Workout unavailable")
                    .font(Theme.Typography.caption)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .accessibilityIdentifier("af_workout_detail_missing_\(workoutID)")
            }
        case .knowledgeDetail(let itemID):
            LibraryDetailView(itemID: itemID) {
                guard let target = viewModel.deleteTarget(forKnowledgeID: itemID) else {
                    return false
                }
                return await viewModel.deleteEntry(target)
            }
        case .onYourWatches:
            OnYourWatchesView(viewModel: watchesVM)
        case .appleScheduled:
            AppleWatchScheduledListView(
                libraryWorkouts: viewModel.allWorkouts.map { ($0.id, $0.name) },
                onScheduleFromLibrary: {
                    navigationPath.append(.libraryPick(.appleSchedule))
                },
                onOpenWorkoutFromWatchItem: { workoutID in
                    navigationPath.append(.unifiedWorkout(workoutID: workoutID))
                }
            )
        case .garminQueue:
            GarminWatchQueueView(
                onPushFromLibrary: {
                    navigationPath.append(.libraryPick(.garminPush))
                },
                onFix: { item in
                    garminFixWorkoutID = item.workoutID
                },
                onOpenWorkoutFromWatchItem: { workoutID in
                    navigationPath.append(.unifiedWorkout(workoutID: workoutID))
                }
            )
        case .libraryPick(let target):
            WatchLibraryPickView(target: target) { workoutID in
                navigationPath.append(.unifiedWorkout(workoutID: workoutID))
            }
        case .collection(let collectionID):
            CollectionDetailView(
                collectionID: collectionID,
                collectionsStore: viewModel.collectionsStore,
                workoutsByID: viewModel.workoutsByID
            ) { workoutID in
                navigationPath.append(.unifiedWorkout(workoutID: workoutID))
            }
        }
    }
}

extension View {
    /// AMA-2376: "+ New" collection name prompt used by Library content.
    func libraryNewCollectionAlert(
        isPresented: Binding<Bool>,
        name: Binding<String>,
        onCreate: @escaping () -> Void
    ) -> some View {
        alert("New Collection", isPresented: isPresented) {
            TextField("Collection name", text: name)
            Button("Cancel", role: .cancel) {
                name.wrappedValue = ""
            }
            Button("Create", action: onCreate)
        } message: {
            Text("Group workouts together, e.g. \u{201C}Hyrox Prep\u{201D} or \u{201C}Push / Pull / Legs\u{201D}.")
        }
    }

    /// AMA-2376: local collection write failures (create / pin / membership).
    func libraryCollectionsFailureAlert(message: Binding<String?>) -> some View {
        alert(
            "Couldn't update collections",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
