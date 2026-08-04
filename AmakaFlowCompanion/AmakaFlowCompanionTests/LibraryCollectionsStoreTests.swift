//
//  LibraryCollectionsStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2376: LibraryCollectionsStore reload/mutators + Uncategorized grid derivation.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class LibraryCollectionsStoreTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: WorkoutCollectionsRepository!
    private var store: LibraryCollectionsStore!

    override func setUp() async throws {
        try await super.setUp()
        db = try AppDatabase.makeTestDatabase()
        repo = WorkoutCollectionsRepository(database: db)
        store = LibraryCollectionsStore(repo: repo)
    }

    override func tearDown() async throws {
        store = nil
        repo = nil
        db = nil
        try await super.tearDown()
    }

    func testReloadPopulatesCollectionsAndPins() throws {
        let collection = try repo.createCollection(name: "Hyrox Prep", note: nil)
        try repo.setPinned(workoutId: "w1", isPinned: true)

        try store.reload()

        XCTAssertEqual(store.collections.map(\.id), [collection.id])
        XCTAssertEqual(store.pinnedIDs, ["w1"])
    }

    func testCreateCollectionForwardsAndReloads() throws {
        try store.createCollection(name: "Runs", note: "5k plan")

        XCTAssertEqual(store.collections.count, 1)
        XCTAssertEqual(store.collections.first?.name, "Runs")
    }

    func testAddMemberForwardsAndReloads() throws {
        let collection = try store.createCollection(name: "PPL", note: nil)
        try store.addMember(collectionId: collection.id, workoutId: "w1")

        XCTAssertEqual(try store.memberWorkoutIds(collectionId: collection.id), ["w1"])
    }

    /// Step 1 brief case: after repo add + prune with a subset, the store's
    /// Uncategorized grid card matches the surviving unfiled workout set.
    func testGridModelsUncategorizedMatchesAfterPrune() throws {
        let collection = try store.createCollection(name: "Hyrox Prep", note: nil)
        try store.addMember(collectionId: collection.id, workoutId: "w1")
        // w2 and w3 are unfiled; w4 is about to be pruned (no longer known).
        try store.setPinned(workoutId: "w4", isPinned: true)

        try store.pruneOrphans(knownWorkoutIds: ["w1", "w2", "w3"])

        let workoutsByID: [String: Workout] = [
            "w1": makeWorkout(id: "w1", duration: 600),
            "w2": makeWorkout(id: "w2", duration: 300),
            "w3": makeWorkout(id: "w3", duration: 900)
        ]
        let grid = store.gridModels(workoutsByID: workoutsByID)

        let uncategorized = grid.first { $0.isUncategorized }
        XCTAssertNotNil(uncategorized)
        XCTAssertEqual(uncategorized?.id, CollectionPresentation.uncategorizedID)
        XCTAssertEqual(Set(uncategorized?.workoutIDs ?? []), ["w2", "w3"])
        XCTAssertEqual(uncategorized?.totalSeconds, 1_200)

        let named = grid.first { !$0.isUncategorized }
        XCTAssertEqual(named?.workoutIDs, ["w1"])
        XCTAssertFalse(store.pinnedIDs.contains("w4"))
    }

    func testGridModelsOmitsUncategorizedWhenNoUnfiledWorkouts() throws {
        let collection = try store.createCollection(name: "PPL", note: nil)
        try store.addMember(collectionId: collection.id, workoutId: "w1")

        let workoutsByID: [String: Workout] = ["w1": makeWorkout(id: "w1", duration: 100)]
        let grid = store.gridModels(workoutsByID: workoutsByID)

        XCTAssertFalse(grid.contains { $0.isUncategorized })
        XCTAssertEqual(grid.count, 1)
    }

    // MARK: - Helpers

    private func makeWorkout(id: String, duration: Int) -> Workout {
        Workout(
            id: id,
            name: id,
            sport: .strength,
            duration: duration,
            blocks: [],
            description: nil,
            source: .manual
        )
    }
}
