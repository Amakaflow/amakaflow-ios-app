//
//  SyncQueueRequestIdTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1823: V2 migration + SyncEngine request_id observability tests.
//

import XCTest
import GRDB
@testable import AmakaFlowCompanion

final class SyncQueueRequestIdTests: XCTestCase {

    // MARK: - V2 Migration

    func testV2MigrationAddsRequestIdColumnAndKeepsExistingRows() throws {
        let database = try AppDatabase.makeTestDatabase()

        // Insert via the regular repository — exercises the post-V2 schema.
        let repo = SyncQueueRepository(
            database: database,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let item = try repo.enqueue(
            resourceType: "workout_events",
            resourceId: "event-1",
            op: "upsert",
            payload: "{}"
        )

        // Column exists, defaults to NULL on enqueue.
        XCTAssertNil(item.requestId)

        // Schema check: request_id column is present on sync_queue.
        let columnNames = try database.dbQueue.read { db -> [String] in
            try db.columns(in: "sync_queue").map(\.name)
        }
        XCTAssertTrue(columnNames.contains("request_id"))

        // Existing rows survive — count is intact.
        let stored = try repo.pending()
        XCTAssertEqual(stored.count, 1)
        XCTAssertNil(stored.first?.requestId)
    }

    func testUpdateRequestIdPersistsValue() throws {
        let database = try AppDatabase.makeTestDatabase()
        let repo = SyncQueueRepository(
            database: database,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let item = try repo.enqueue(
            resourceType: "accepted_suggestions",
            resourceId: "sugg-1",
            op: "upsert",
            payload: "{}"
        )

        let requestId = "11111111-2222-3333-4444-555555555555"
        try repo.updateRequestId(item.id, requestId: requestId)

        let reloaded = try repo.pending().first
        XCTAssertEqual(reloaded?.requestId, requestId)
    }

    // MARK: - SyncEngine UUID Injection

    @MainActor
    func testSyncEngineStampsRequestIdOnQueueRowAndForwardsToHandler() async throws {
        let database = try AppDatabase.makeTestDatabase()
        let now = Date(timeIntervalSince1970: 3_000)
        let repo = SyncQueueRepository(database: database, now: { now })

        let queued = try repo.enqueue(
            resourceType: "workout_events",
            resourceId: "event-77",
            op: "upsert",
            payload: "{}"
        )
        XCTAssertNil(queued.requestId)

        // Capture the request_id the SyncEngine forwards to the handler.
        let captured = ItemCapture()
        let engine = SyncEngine(
            queueRepository: repo,
            maxAttempts: 3,
            baseBackoff: 1,
            completedRetention: 60,
            syncHandler: { item in
                await captured.set(item)
            }
        )

        await engine.processPending()

        let observed = await captured.value
        let observedRequestId = try XCTUnwrap(observed?.requestId)
        XCTAssertFalse(observedRequestId.isEmpty)
        XCTAssertNotNil(UUID(uuidString: observedRequestId), "request_id should be a valid UUID")

        // Persisted on the row even after success (markSynced doesn't clear it).
        let persisted = try await database.dbQueue.read { db in
            try SyncQueueItem.fetchOne(db, key: queued.id)
        }
        XCTAssertEqual(persisted?.requestId, observedRequestId)
        XCTAssertEqual(persisted?.status, .synced)
    }

    @MainActor
    func testSyncEngineGeneratesFreshRequestIdPerAttempt() async throws {
        let database = try AppDatabase.makeTestDatabase()
        let now = Date(timeIntervalSince1970: 4_000)
        let repo = SyncQueueRepository(database: database, now: { now })

        let queued = try repo.enqueue(
            resourceType: "workout_events",
            resourceId: "event-99",
            op: "upsert",
            payload: "{}"
        )

        let observedIds = IdCollector()
        let engine = SyncEngine(
            queueRepository: repo,
            maxAttempts: 5,
            baseBackoff: 0,
            completedRetention: 60,
            syncHandler: { item in
                if let id = item.requestId {
                    await observedIds.append(id)
                }
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
            }
        )

        // Process twice; the engine pulls failed rows whose next_attempt_at
        // has elapsed. Force eligibility by clearing next_attempt_at between
        // runs (pending() filter only excludes rows with next_attempt_at >
        // now, and our test clock returns the same `now` every read).
        await engine.processPending()
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sync_queue SET next_attempt_at = NULL WHERE id = ?",
                arguments: [queued.id]
            )
        }
        await engine.processPending()

        let ids = await observedIds.values
        XCTAssertEqual(ids.count, 2, "handler should be called once per attempt")
        XCTAssertNotEqual(ids[0], ids[1], "each attempt must generate a fresh request_id")
        XCTAssertNotNil(UUID(uuidString: ids[0]))
        XCTAssertNotNil(UUID(uuidString: ids[1]))

        // Final persisted value matches the most recent attempt.
        let persisted = try await database.dbQueue.read { db in
            try SyncQueueItem.fetchOne(db, key: queued.id)
        }
        XCTAssertEqual(persisted?.requestId, ids.last)
    }
}

// MARK: - Test Helpers

private actor ItemCapture {
    private(set) var value: SyncQueueItem?
    func set(_ item: SyncQueueItem) { self.value = item }
}

private actor IdCollector {
    private(set) var values: [String] = []
    func append(_ id: String) { values.append(id) }
}
