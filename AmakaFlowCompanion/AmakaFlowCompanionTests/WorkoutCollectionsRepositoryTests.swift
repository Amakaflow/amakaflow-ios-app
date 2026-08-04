//
//  WorkoutCollectionsRepositoryTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2376: local-first workout collections and pins.
//

import XCTest
import GRDB
@testable import AmakaFlowCompanion

final class WorkoutCollectionsRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: WorkoutCollectionsRepository!
    private var clock: Date!

    override func setUp() async throws {
        clock = Date(timeIntervalSince1970: 1_700_000_000)
        db = try AppDatabase.makeTestDatabase()
        repo = WorkoutCollectionsRepository(database: db, now: { self.clock })
    }

    func testCreateAddMultiMembershipAndUncategorized() throws {
        let a = try repo.createCollection(name: "Hyrox Prep", note: nil)
        let b = try repo.createCollection(name: "Runs", note: nil)
        try repo.addMember(collectionId: a.id, workoutId: "w1")
        try repo.addMember(collectionId: a.id, workoutId: "w2")
        try repo.addMember(collectionId: b.id, workoutId: "w1") // multi
        let known: Set = ["w1", "w2", "w3"]
        XCTAssertEqual(try repo.uncategorizedWorkoutIds(from: known), ["w3"])
        XCTAssertEqual(Set(try repo.collectionIds(containing: "w1")), Set([a.id, b.id]))
    }

    func testAddAppendsMaxPlusOnePosition() throws {
        let c = try repo.createCollection(name: "PPL", note: nil)
        try repo.addMember(collectionId: c.id, workoutId: "w1")
        try repo.addMember(collectionId: c.id, workoutId: "w2")
        let ids = try repo.memberWorkoutIds(collectionId: c.id)
        XCTAssertEqual(ids, ["w1", "w2"])
        // Inspect positions via direct SQL or public helper if exposed
        let positions = try db.dbQueue.read { db in
            try Int.fetchAll(db, sql: """
                SELECT position FROM workout_collection_members
                WHERE collection_id = ? ORDER BY position
                """, arguments: [c.id])
        }
        XCTAssertEqual(positions, [1, 2])
    }

    func testRemoveMemberKeepsWorkoutConceptuallyAndUpdatesRecency() throws {
        let c = try repo.createCollection(name: "Hyrox Prep", note: nil)
        try repo.addMember(collectionId: c.id, workoutId: "w1")
        clock = clock.addingTimeInterval(60)
        try repo.removeMember(collectionId: c.id, workoutId: "w1")
        XCTAssertTrue(try repo.memberWorkoutIds(collectionId: c.id).isEmpty)
        let list = try repo.listCollections()
        XCTAssertEqual(list.first?.id, c.id)
    }

    func testPinToggleAndListOrder() throws {
        try repo.setPinned(workoutId: "w1", isPinned: true)
        clock = clock.addingTimeInterval(10)
        try repo.setPinned(workoutId: "w2", isPinned: true)
        XCTAssertEqual(try repo.listPinnedWorkoutIds(), ["w2", "w1"])
        try repo.setPinned(workoutId: "w1", isPinned: false)
        XCTAssertEqual(try repo.listPinnedWorkoutIds(), ["w2"])
    }

    func testPruneOrphansRemovesMembershipsAndPins() throws {
        let c = try repo.createCollection(name: "Hyrox Prep", note: nil)
        try repo.addMember(collectionId: c.id, workoutId: "gone")
        try repo.addMember(collectionId: c.id, workoutId: "keep")
        try repo.setPinned(workoutId: "gone", isPinned: true)
        let removed = try repo.pruneOrphans(knownWorkoutIds: ["keep"])
        XCTAssertGreaterThanOrEqual(removed, 2)
        XCTAssertEqual(try repo.memberWorkoutIds(collectionId: c.id), ["keep"])
        XCTAssertFalse(try repo.isPinned(workoutId: "gone"))
        XCTAssertEqual(try repo.uncategorizedWorkoutIds(from: ["keep"]), [])
    }

    func testMoveMembersBetweenCollections() throws {
        let from = try repo.createCollection(name: "A", note: nil)
        let to = try repo.createCollection(name: "B", note: nil)
        try repo.addMember(collectionId: from.id, workoutId: "w1")
        try repo.moveMembers(workoutIds: ["w1"], fromCollectionId: from.id, toCollectionId: to.id)
        XCTAssertTrue(try repo.memberWorkoutIds(collectionId: from.id).isEmpty)
        XCTAssertEqual(try repo.memberWorkoutIds(collectionId: to.id), ["w1"])
    }

    func testAddMembersBatchesInsertsInSourceOrder() throws {
        let collection = try repo.createCollection(name: "Hyrox Prep", note: nil)
        try repo.addMembers(collectionId: collection.id, workoutIds: ["w1", "w2", "w3"])
        XCTAssertEqual(try repo.memberWorkoutIds(collectionId: collection.id), ["w1", "w2", "w3"])
        // Idempotent — already-members are skipped without shifting positions.
        try repo.addMembers(collectionId: collection.id, workoutIds: ["w2", "w4"])
        XCTAssertEqual(try repo.memberWorkoutIds(collectionId: collection.id), ["w1", "w2", "w3", "w4"])
    }
}
