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
    /// AMA-2376: member workout IDs per collection, refreshed on every `reload()`.
    /// `gridModels` / `CollectionDetailView` read this instead of hitting SQLite
    /// once per named collection on every SwiftUI render (N+1 read path).
    @Published private(set) var membersByCollectionID: [String: [String]] = [:]

    private let repo: WorkoutCollectionsRepository
    /// Memoizes `uncategorizedWorkoutIds(workoutsByID:)` for the last-seen known-ID
    /// set so repeated renders with an unchanged workout set don't re-query SQLite.
    /// Invalidated on every `reload()` since membership may have changed underneath.
    private var uncategorizedCacheKey: Set<String>?
    private var uncategorizedCacheValue: [String] = []

    init(repo: WorkoutCollectionsRepository = WorkoutCollectionsRepository()) {
        self.repo = repo
    }

    /// Re-reads collections + pins from the repository, and re-populates the
    /// per-collection member cache used by `gridModels` / `memberWorkoutIds`.
    func reload() throws {
        collections = try repo.listCollections()
        pinnedIDs = try repo.listPinnedWorkoutIds()
        var membersMap: [String: [String]] = [:]
        for collection in collections {
            membersMap[collection.id] = try repo.memberWorkoutIds(collectionId: collection.id)
        }
        membersByCollectionID = membersMap
        uncategorizedCacheKey = nil
        uncategorizedCacheValue = []
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

    /// Batch add — single `reload()` after all inserts (avoids N full store refreshes).
    func addMembers(collectionId: String, workoutIds: [String]) throws {
        try repo.addMembers(collectionId: collectionId, workoutIds: workoutIds)
        try reload()
    }

    func removeMember(collectionId: String, workoutId: String) throws {
        try repo.removeMember(collectionId: collectionId, workoutId: workoutId)
        try reload()
    }

    func moveMembers(workoutIds: [String], fromCollectionId: String, toCollectionId: String) throws {
        try repo.moveMembers(
            workoutIds: workoutIds,
            fromCollectionId: fromCollectionId,
            toCollectionId: toCollectionId
        )
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

    /// Reads from the `reload()`-populated cache — no SQLite hit on the common path.
    /// Falls back to a direct repo read if called before any `reload()` has happened.
    func memberWorkoutIds(collectionId: String) throws -> [String] {
        if let cached = membersByCollectionID[collectionId] {
            return cached
        }
        return try repo.memberWorkoutIds(collectionId: collectionId)
    }

    /// Real collections (never the derived Uncategorized bucket) currently containing
    /// `workoutId` — drives detail chips (AMA-2376 Task 7). Reads the same cache as
    /// `memberWorkoutIds` rather than issuing its own query per call.
    func collections(containing workoutId: String) -> [LocalWorkoutCollection] {
        collections.filter { membersByCollectionID[$0.id]?.contains(workoutId) ?? false }
    }

    /// Uncategorized member ids for the given known workouts — always reflects the
    /// current unfiled set, even when empty (unlike `gridModels`, which hides the
    /// empty Uncategorized card). Used by `CollectionDetailView` for the derived folder.
    /// Memoized against the last-seen known-ID set so repeated calls with an unchanged
    /// `workoutsByID` (e.g. across SwiftUI re-renders) don't re-query SQLite.
    func uncategorizedWorkoutIds(workoutsByID: [String: Workout]) -> [String] {
        let knownIDs = Set(workoutsByID.keys)
        if uncategorizedCacheKey == knownIDs {
            return uncategorizedCacheValue
        }
        let result = (try? repo.uncategorizedWorkoutIds(from: knownIDs)) ?? []
        uncategorizedCacheKey = knownIDs
        uncategorizedCacheValue = result
        return result
    }

    /// Grid cards for the Library collections screen: one per named collection,
    /// plus a derived Uncategorized folder when any known workout has no membership.
    /// Reads member IDs from the `reload()`-populated cache instead of hitting SQLite
    /// once per collection on every SwiftUI render (N+1 read path).
    func gridModels(workoutsByID: [String: Workout]) -> [CollectionGridItem] {
        var items: [CollectionGridItem] = collections.compactMap { collection in
            guard let workoutIDs = membersByCollectionID[collection.id] else { return nil }
            return CollectionGridItem(
                id: collection.id,
                name: collection.name,
                workoutIDs: workoutIDs,
                totalSeconds: Self.totalSeconds(for: workoutIDs, workoutsByID: workoutsByID),
                isUncategorized: false
            )
        }

        let unfiled = uncategorizedWorkoutIds(workoutsByID: workoutsByID)
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
