//
//  SuggestionAcceptanceServiceTests.swift
//  AmakaFlowCompanionTests
//
//  Issue #435 — SuggestionAcceptanceService seam tests.
//  Asserts: (1) happy path writes both rows and enqueues sync items;
//  (2) when enqueue fails the accept transaction is rolled back;
//  (3) mismatched-userId invariant propagates as a throw with no rows written.
//

import XCTest
import GRDB
@testable import AmakaFlowCompanion

final class SuggestionAcceptanceServiceTests: XCTestCase {

    private let userId = "user-sas-435"
    private let baseTimestamp = Date(timeIntervalSince1970: 60_000)

    private func makeService(database: AppDatabase) -> (SuggestionAcceptanceService, AcceptedSuggestionsRepository, SyncQueueRepository) {
        let syncQueue = SyncQueueRepository(database: database, now: { self.baseTimestamp })
        let repo = AcceptedSuggestionsRepository(database: database, syncQueue: syncQueue, now: { self.baseTimestamp })
        let service = SuggestionAcceptanceService(repository: repo)
        return (service, repo, syncQueue)
    }

    private func makeAccept(id: String, eventId: String) -> (LocalAcceptedSuggestion, LocalWorkoutEvent) {
        let event = LocalWorkoutEvent(
            id: eventId,
            userId: userId,
            date: "2026-07-08",
            startTime: "07:00",
            endTime: "08:00",
            status: "planned",
            source: "suggestion_accepted",
            jsonPayload: "{}",
            clientGeneratedId: "cgid-\(eventId)",
            serverVersion: 0,
            createdAt: baseTimestamp,
            updatedAt: baseTimestamp,
            deletedAt: nil
        )
        let suggestion = LocalAcceptedSuggestion(
            id: id,
            userId: userId,
            suggestionId: nil,
            workoutEventId: eventId,
            status: "accepted",
            clientGeneratedId: "cgid-\(id)",
            serverVersion: 0,
            createdAt: baseTimestamp,
            updatedAt: baseTimestamp,
            deletedAt: nil
        )
        return (suggestion, event)
    }

    // MARK: - Happy path

    func test_accept__happyPath__writesRowAndEnqueuesSyncItems() throws {
        let database = try AppDatabase.makeTestDatabase()
        let (service, repo, syncQueue) = makeService(database: database)
        let (suggestion, event) = makeAccept(id: "sugg-happy", eventId: "evt-happy")

        try service.accept(userId: userId, suggestion: suggestion, event: event)

        let live = try repo.pendingForUser(userId)
        XCTAssertEqual(live.count, 1, "accepted suggestion must be persisted")
        XCTAssertEqual(live.first?.id, "sugg-happy")

        let queue = try syncQueue.pending()
        let suggestionUpserts = queue.filter { $0.resourceType == "accepted_suggestions" && $0.op == "upsert" }
        let eventUpserts = queue.filter { $0.resourceType == "workout_events" && $0.op == "upsert" }
        XCTAssertEqual(suggestionUpserts.count, 1, "one sync_queue upsert must be enqueued for the accepted_suggestion")
        XCTAssertEqual(eventUpserts.count, 1, "one sync_queue upsert must be enqueued for the workout_event")
    }

    // MARK: - Rollback on enqueue failure

    func test_accept__enqueueFailure__rollsBackAcceptRow() throws {
        let database = try AppDatabase.makeTestDatabase()

        // Drop sync_queue so the enqueue inside the transaction throws,
        // causing the GRDB write to roll back the accept row as well.
        try database.dbQueue.write { db in
            try db.execute(sql: "DROP TABLE sync_queue")
        }

        let (service, repo, _) = makeService(database: database)
        let (suggestion, event) = makeAccept(id: "sugg-rollback", eventId: "evt-rollback")

        XCTAssertThrowsError(
            try service.accept(userId: userId, suggestion: suggestion, event: event),
            "accept must throw when enqueue fails (no sync_queue table)"
        )

        let live = try repo.pendingForUser(userId)
        XCTAssertEqual(live.count, 0, "accept row must be rolled back when enqueue fails inside the transaction")

        let eventRow = try database.dbQueue.read { db in
            try LocalWorkoutEvent.fetchOne(db, key: "evt-rollback")
        }
        XCTAssertNil(eventRow, "workout_event row must be rolled back when enqueue fails inside the transaction")
    }

    // MARK: - Invariant guard propagates

    func test_accept__mismatchedUserId__throwsWithoutWriting() throws {
        let database = try AppDatabase.makeTestDatabase()
        let (service, repo, _) = makeService(database: database)

        var (suggestion, event) = makeAccept(id: "sugg-mismatch", eventId: "evt-mismatch")
        suggestion = LocalAcceptedSuggestion(
            id: suggestion.id,
            userId: "different-user",
            suggestionId: nil,
            workoutEventId: event.id,
            status: "accepted",
            clientGeneratedId: suggestion.clientGeneratedId,
            serverVersion: 0,
            createdAt: baseTimestamp,
            updatedAt: baseTimestamp,
            deletedAt: nil
        )

        XCTAssertThrowsError(
            try service.accept(userId: userId, suggestion: suggestion, event: event),
            "invariant guard must throw when suggestion.userId != userId"
        )

        let live = try repo.pendingForUser(userId)
        XCTAssertEqual(live.count, 0, "no rows must be written when invariant fires")
    }
}
