//
//  LibraryCollectionsStore.swift
//  AmakaFlow
//
//  AMA-2376: local-first Library collections state; forwards to
//  WorkoutCollectionsRepository and re-reads after every mutation.
//

import Combine
import Foundation

/// Grid card model for a Library collections folder, including the derived
/// Uncategorized folder (not a DB row — see `CollectionPresentation.uncategorizedID`).
struct CollectionGridItem: Identifiable, Equatable {
    let id: String
    let name: String
    let workoutIDs: [String]
    let totalSeconds: Int
    let isUncategorized: Bool
}

@MainActor
final class LibraryCollectionsStore: ObservableObject {
    @Published private(set) var collections: [LocalWorkoutCollection] = []
    @Published private(set) var pinnedIDs: [String] = []

    private let repo: WorkoutCollectionsRepository

    init(repo: WorkoutCollectionsRepository = WorkoutCollectionsRepository()) {
        self.repo = repo
    }

    /// Re-reads collections + pins from the repository.
    func reload() throws {
        collections = try repo.listCollections()
        pinnedIDs = try repo.listPinnedWorkoutIds()
    }

    @discardableResult
    func createCollection(name: String, note: String?) throws -> LocalWorkoutCollection {
        let created = try repo.createCollection(name: name, note: note)
        try reload()
        return created
    }

    func renameCollection(id: String, name: String, note: String?) throws {
        try repo.renameCollection(id: id, name: name, note: note)
        try reload()
    }

    func deleteCollection(id: String) throws {
        try repo.deleteCollection(id: id)
        try reload()
    }

    func addMember(collectionId: String, workoutId: String) throws {
        try repo.addMember(collectionId: collectionId, workoutId: workoutId)
        try reload()
    }

    func removeMember(collectionId: String, workoutId: String) throws {
        try repo.removeMember(collectionId: collectionId, workoutId: workoutId)
        try reload()
    }

    func moveMembers(workoutIds: [String], from: String, to: String) throws {
        try repo.moveMembers(workoutIds: workoutIds, from: from, to: to)
        try reload()
    }

    func setPinned(workoutId: String, isPinned: Bool) throws {
        try repo.setPinned(workoutId: workoutId, isPinned: isPinned)
        try reload()
    }

    /// Removes memberships/pins for workouts that no longer exist, then refreshes.
    @discardableResult
    func pruneOrphans(knownWorkoutIds: Set<String>) throws -> Int {
        let removed = try repo.pruneOrphans(knownWorkoutIds: knownWorkoutIds)
        try reload()
        return removed
    }

    func memberWorkoutIds(collectionId: String) throws -> [String] {
        try repo.memberWorkoutIds(collectionId: collectionId)
    }

    /// Grid cards for the Library collections screen: one per named collection,
    /// plus a derived Uncategorized folder when any known workout has no membership.
    /// Errors from the underlying repo are swallowed — local-first reads should
    /// degrade to an empty/partial grid rather than crash the Library tab.
    func gridModels(workoutsByID: [String: Workout]) -> [CollectionGridItem] {
        var items: [CollectionGridItem] = collections.compactMap { collection in
            guard let workoutIDs = try? repo.memberWorkoutIds(collectionId: collection.id) else { return nil }
            return CollectionGridItem(
                id: collection.id,
                name: collection.name,
                workoutIDs: workoutIDs,
                totalSeconds: Self.totalSeconds(for: workoutIDs, workoutsByID: workoutsByID),
                isUncategorized: false
            )
        }

        let unfiled = (try? repo.uncategorizedWorkoutIds(from: Set(workoutsByID.keys))) ?? []
        if !unfiled.isEmpty {
            items.append(
                CollectionGridItem(
                    id: CollectionPresentation.uncategorizedID,
                    name: "Uncategorized",
                    workoutIDs: unfiled,
                    totalSeconds: Self.totalSeconds(for: unfiled, workoutsByID: workoutsByID),
                    isUncategorized: true
                )
            )
        }

        return items
    }

    private static func totalSeconds(for workoutIDs: [String], workoutsByID: [String: Workout]) -> Int {
        workoutIDs.compactMap { workoutsByID[$0]?.duration }.reduce(0, +)
    }
}
