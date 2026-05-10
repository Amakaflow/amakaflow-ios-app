//
//  AMA1839_CJ01_SyncEngine_RequestIdTests.swift
//  AmakaFlowCompanionTests
//
//  CJ-01 / L2 — Local state transition: every queued mutation produced by
//  the Save & End flow gets a fresh request_id per attempt, the same id
//  reaches the upstream sync handler (which forwards it as X-Request-ID),
//  and the row's persisted column reflects the most recent attempt.
//
//  Companion to SyncQueueRequestIdTests (AMA-1823); this file pins the
//  CJ-01-specific invariants: handler-arg ↔ row-column equality on success,
//  three-attempt UUID uniqueness, and validity of every emitted UUID.
//

import XCTest
import GRDB
@testable import AmakaFlowCompanion

final class AMA1839_CJ01_SyncEngine_RequestIdTests: XCTestCase {

    @MainActor
    func test_syncEngine__successfulAttempt__handlerArgRequestIdMatchesPersistedRow() async throws {
        let database = try AppDatabase.makeTestDatabase()
        let now = Date(timeIntervalSince1970: 10_000)
        let repo = SyncQueueRepository(database: database, now: { now })

        let queued = try repo.enqueue(
            resourceType: "workout_events",
            resourceId: "cj01-event-1",
            op: "upsert",
            payload: "{}"
        )

        let captured = ItemCapture()
        let engine = SyncEngine(
            queueRepository: repo,
            maxAttempts: 3,
            baseBackoff: 0,
            completedRetention: 60,
            syncHandler: { item in await captured.set(item) }
        )

        await engine.processPending()

        let observedItem = await captured.value
        let handlerItem = try XCTUnwrap(observedItem, "syncHandler must be invoked exactly once for a pending row")
        let handlerRequestId = try XCTUnwrap(handlerItem.requestId, "handler must observe a non-nil request_id (becomes X-Request-ID header)")

        let row = try await database.dbQueue.read { db in
            try SyncQueueItem.fetchOne(db, key: queued.id)
        }
        XCTAssertEqual(row?.requestId, handlerRequestId,
                       "request_id seen by the upstream handler must equal the value persisted on the sync_queue row (CJ-01 observability invariant)")
        XCTAssertEqual(row?.status, .synced,
                       "successful Save & End queue item must end in .synced status")
    }

    @MainActor
    func test_syncEngine__threeAttemptsAcrossRetries__eachAttemptUsesUniqueValidUUID() async throws {
        let database = try AppDatabase.makeTestDatabase()
        let now = Date(timeIntervalSince1970: 20_000)
        let repo = SyncQueueRepository(database: database, now: { now })

        let queued = try repo.enqueue(
            resourceType: "accepted_suggestions",
            resourceId: "cj01-sugg-1",
            op: "upsert",
            payload: "{}"
        )

        let collector = IdCollector()
        let engine = SyncEngine(
            queueRepository: repo,
            maxAttempts: 5,
            baseBackoff: 0,
            completedRetention: 60,
            syncHandler: { item in
                if let id = item.requestId { await collector.append(id) }
                throw NSError(domain: "cj01.test", code: 1, userInfo: [NSLocalizedDescriptionKey: "transient"])
            }
        )

        // Three attempts; clear next_attempt_at between runs so the row stays eligible.
        for _ in 0..<3 {
            await engine.processPending()
            try await database.dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE sync_queue SET next_attempt_at = NULL, status = 'pending' WHERE id = ?",
                    arguments: [queued.id]
                )
            }
        }

        let ids = await collector.values
        XCTAssertEqual(ids.count, 3, "handler must be invoked once per attempt")
        XCTAssertEqual(Set(ids).count, 3, "every retry attempt must generate a fresh request_id (CJ-01: each /completions retry must be independently traceable in BFF logs)")
        for (i, id) in ids.enumerated() {
            XCTAssertNotNil(UUID(uuidString: id), "attempt \(i + 1) request_id (\(id)) must be a valid RFC 4122 UUID")
        }
    }
}

// MARK: - Helpers

private actor ItemCapture {
    private(set) var value: SyncQueueItem?
    func set(_ item: SyncQueueItem) { self.value = item }
}

private actor IdCollector {
    private(set) var values: [String] = []
    func append(_ id: String) { values.append(id) }
}
