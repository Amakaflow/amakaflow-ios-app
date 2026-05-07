//
//  LocalFirstStorageTests.swift
//  AmakaFlowCompanionTests
//

import XCTest
import GRDB
@testable import AmakaFlowCompanion

final class LocalFirstStorageTests: XCTestCase {
    func testV1MigrationCreatesExpectedTables() throws {
        let database = try AppDatabase.makeTestDatabase()
        let tables = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }

        XCTAssertTrue(tables.contains("accepted_suggestions"))
        XCTAssertTrue(tables.contains("workout_events"))
        XCTAssertTrue(tables.contains("ai_runs"))
        XCTAssertTrue(tables.contains("sync_queue"))
    }

    func testAcceptedSuggestionInsertEnqueuesSyncItem() throws {
        let database = try AppDatabase.makeTestDatabase()
        let syncQueue = SyncQueueRepository(database: database, now: { Date(timeIntervalSince1970: 1_000) })
        let repository = AcceptedSuggestionsRepository(database: database, syncQueue: syncQueue, now: { Date(timeIntervalSince1970: 1_000) })

        let suggestion = LocalAcceptedSuggestion(
            id: "accepted-1",
            userId: "user-1",
            suggestionId: nil,
            workoutEventId: nil,
            status: "accepted",
            clientGeneratedId: "client-1",
            serverVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000),
            deletedAt: nil
        )

        try repository.insert(suggestion)

        let stored = try repository.pendingForUser("user-1")
        XCTAssertEqual(stored, [suggestion])

        let queued = try syncQueue.pending()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.resourceType, "accepted_suggestions")
        XCTAssertEqual(queued.first?.resourceId, "accepted-1")
        XCTAssertEqual(queued.first?.op, "upsert")
    }

    func testWorkoutEventsDateRangeAndSyncQueueSummary() throws {
        let database = try AppDatabase.makeTestDatabase()
        let syncQueue = SyncQueueRepository(database: database, now: { Date(timeIntervalSince1970: 2_000) })
        let repository = WorkoutEventsRepository(database: database, syncQueue: syncQueue, now: { Date(timeIntervalSince1970: 2_000) })

        let event = LocalWorkoutEvent(
            id: "event-1",
            userId: "user-1",
            date: "2026-05-08",
            startTime: "07:00",
            endTime: nil,
            status: "planned",
            source: "suggestion_accepted",
            jsonPayload: "{\"name\":\"Easy Run\"}",
            clientGeneratedId: "event-client-1",
            serverVersion: 1,
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            deletedAt: nil
        )

        try repository.upsert(event)

        let events = try repository.eventsForUser("user-1", from: "2026-05-08", to: "2026-05-08")
        XCTAssertEqual(events, [event])

        let summary = try syncQueue.summary()
        XCTAssertEqual(summary.pendingCount, 1)
        XCTAssertEqual(summary.poisonCount, 0)
    }

    func testSyncQueueFailureBecomesPoisonAfterMaxAttempts() throws {
        let database = try AppDatabase.makeTestDatabase()
        let syncQueue = SyncQueueRepository(database: database, now: { Date(timeIntervalSince1970: 3_000) })
        let item = try syncQueue.enqueue(resourceType: "workout_events", resourceId: "event-1", op: "upsert", payload: "{}")

        try syncQueue.markFailed(item.id, error: "network", retryAfter: 1, poisonAfter: 1)

        let summary = try syncQueue.summary()
        XCTAssertEqual(summary.pendingCount, 0)
        XCTAssertEqual(summary.poisonCount, 1)
        XCTAssertEqual(summary.latestError, "network")
    }
}
