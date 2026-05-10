//
//  AMA1839_CJ01_AcceptedSuggestions_ReplaceOnAcceptTests.swift
//  AmakaFlowCompanionTests
//
//  CJ-01 / L2 — Local state transition: replacePriorAcceptsAndInsert
//  (AMA-1815 hotfix) atomically tombstones every prior live accept + its
//  paired workout_event in the same transaction that inserts the new pair.
//
//  This is the contract that keeps Quick Start / Today showing exactly ONE
//  accepted suggestion in the CJ-01 Generate → Save & End loop. Without it
//  the AMA-1792 GRDB rewire surfaced the full historical accept list.
//

import XCTest
import GRDB
@testable import AmakaFlowCompanion

final class AMA1839_CJ01_AcceptedSuggestions_ReplaceOnAcceptTests: XCTestCase {

    private let userId = "user-cj01"
    private let baseTimestamp = Date(timeIntervalSince1970: 50_000)

    private func makeRepo(database: AppDatabase, now: @escaping () -> Date) -> (AcceptedSuggestionsRepository, SyncQueueRepository, WorkoutEventsRepository) {
        let syncQueue = SyncQueueRepository(database: database, now: now)
        let suggestions = AcceptedSuggestionsRepository(database: database, syncQueue: syncQueue, now: now)
        let events = WorkoutEventsRepository(database: database, syncQueue: syncQueue, now: now)
        return (suggestions, syncQueue, events)
    }

    private func makeAccept(
        id: String,
        eventId: String,
        userId: String,
        timestamp: Date
    ) -> (LocalAcceptedSuggestion, LocalWorkoutEvent) {
        let event = LocalWorkoutEvent(
            id: eventId,
            userId: userId,
            date: "2026-05-09",
            startTime: "08:00",
            endTime: "08:30",
            status: "planned",
            source: "suggestion_accepted",
            jsonPayload: "{}",
            clientGeneratedId: "cgid-\(eventId)",
            serverVersion: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )
        let suggestion = LocalAcceptedSuggestion(
            id: id,
            userId: userId,
            suggestionId: nil,
            workoutEventId: eventId,
            status: "accepted",
            clientGeneratedId: "cgid-\(id)",
            serverVersion: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )
        return (suggestion, event)
    }

    // MARK: - Tests

    func test_acceptedSuggestions__secondAcceptAfterFirst__tombstonesPriorAtomically() throws {
        let database = try AppDatabase.makeTestDatabase()
        let (repo, _, eventsRepo) = makeRepo(database: database, now: { self.baseTimestamp })

        // First accept lands and is live.
        let (firstSuggestion, firstEvent) = makeAccept(id: "sugg-1", eventId: "evt-1", userId: userId, timestamp: baseTimestamp)
        try repo.replacePriorAcceptsAndInsert(userId: userId, suggestion: firstSuggestion, event: firstEvent, enqueueSync: false)

        // Second accept must supersede the first inside one transaction.
        let secondTimestamp = baseTimestamp.addingTimeInterval(60)
        let (secondSuggestion, secondEvent) = makeAccept(id: "sugg-2", eventId: "evt-2", userId: userId, timestamp: secondTimestamp)
        let (repo2, _, _) = makeRepo(database: database, now: { secondTimestamp })
        try repo2.replacePriorAcceptsAndInsert(userId: userId, suggestion: secondSuggestion, event: secondEvent, enqueueSync: false)

        // Live accept set is exactly the new pair.
        let live = try repo2.pendingForUser(userId)
        XCTAssertEqual(live.count, 1, "after replace-on-accept exactly one accepted suggestion must remain live for the user")
        XCTAssertEqual(live.first?.id, "sugg-2", "live row must be the most recently inserted accept (CJ-01: Quick Start should show the freshly generated workout, not stale ones)")

        // Prior suggestion is tombstoned, not deleted.
        let all = try repo2.allForUser(userId)
        let prior = try XCTUnwrap(all.first(where: { $0.id == "sugg-1" }), "prior accept must be retained as a tombstoned row, not hard-deleted")
        XCTAssertEqual(prior.status, "deleted", "prior accept status must transition to 'deleted'")
        XCTAssertNotNil(prior.deletedAt, "prior accept must carry a deleted_at timestamp")

        // Paired prior workout_event is also tombstoned (so hydrateIncoming won't resurrect it).
        let priorEvent = try database.dbQueue.read { db in
            try LocalWorkoutEvent.fetchOne(db, key: "evt-1")
        }
        let unwrappedPriorEvent = try XCTUnwrap(priorEvent, "prior workout_event row must still exist (tombstoned, not hard-deleted)")
        XCTAssertNotNil(unwrappedPriorEvent.deletedAt,
                        "prior workout_event must be tombstoned in the same transaction so hydrateIncoming cannot resurrect it on next launch")

        // New pair is live + visible from the events repo.
        let todays = try eventsRepo.todayPlan(userId: userId, date: makeDate("2026-05-09"))
        XCTAssertTrue(todays.contains(where: { $0.id == "evt-2" }),
                      "freshly accepted workout_event must appear in today's plan after replace-on-accept")
        XCTAssertFalse(todays.contains(where: { $0.id == "evt-1" }),
                       "tombstoned workout_event must NOT appear in today's plan")
    }

    func test_acceptedSuggestions__replaceOnAccept__enqueuesDeletePerPriorAndUpsertForNewPair() throws {
        let database = try AppDatabase.makeTestDatabase()
        let (repo, syncQueue, _) = makeRepo(database: database, now: { self.baseTimestamp })

        let (firstSuggestion, firstEvent) = makeAccept(id: "sugg-A", eventId: "evt-A", userId: userId, timestamp: baseTimestamp)
        try repo.replacePriorAcceptsAndInsert(userId: userId, suggestion: firstSuggestion, event: firstEvent, enqueueSync: true)

        let later = baseTimestamp.addingTimeInterval(120)
        let (secondSuggestion, secondEvent) = makeAccept(id: "sugg-B", eventId: "evt-B", userId: userId, timestamp: later)
        let (repo2, syncQueue2, _) = makeRepo(database: database, now: { later })
        try repo2.replacePriorAcceptsAndInsert(userId: userId, suggestion: secondSuggestion, event: secondEvent, enqueueSync: true)

        let pending = try syncQueue2.pending()

        let suggestionDeletes = pending.filter { $0.resourceType == "accepted_suggestions" && $0.op == "delete" }
        let eventDeletes = pending.filter { $0.resourceType == "workout_events" && $0.op == "delete" }
        let suggestionUpserts = pending.filter { $0.resourceType == "accepted_suggestions" && $0.op == "upsert" && $0.resourceId == "sugg-B" }
        let eventUpserts = pending.filter { $0.resourceType == "workout_events" && $0.op == "upsert" && $0.resourceId == "evt-B" }

        XCTAssertEqual(suggestionDeletes.count, 1, "exactly one delete enqueued for the prior accepted_suggestion (sugg-A)")
        XCTAssertEqual(suggestionDeletes.first?.resourceId, "sugg-A", "delete must target the prior suggestion id")
        XCTAssertEqual(eventDeletes.count, 1, "exactly one delete enqueued for the prior workout_event (evt-A)")
        XCTAssertEqual(eventDeletes.first?.resourceId, "evt-A", "delete must target the prior workout_event id")
        XCTAssertEqual(suggestionUpserts.count, 1, "the new accepted_suggestion must enqueue an upsert")
        XCTAssertEqual(eventUpserts.count, 1, "the new workout_event must enqueue an upsert")
        _ = syncQueue
    }

    func test_acceptedSuggestions__mismatchedUserIdInvariant__throwsWithoutWriting() throws {
        let database = try AppDatabase.makeTestDatabase()
        let (repo, _, _) = makeRepo(database: database, now: { self.baseTimestamp })

        let (otherUserSuggestion, otherUserEvent) = makeAccept(id: "sugg-X", eventId: "evt-X", userId: "different-user", timestamp: baseTimestamp)

        XCTAssertThrowsError(
            try repo.replacePriorAcceptsAndInsert(userId: userId, suggestion: otherUserSuggestion, event: otherUserEvent, enqueueSync: false),
            "invariant must reject suggestion/event whose userId mismatches the userId arg (cross-user data corruption guard)"
        )

        let live = try repo.pendingForUser(userId)
        XCTAssertEqual(live.count, 0, "no rows must be written when the invariant fires")
    }

    // MARK: - Helpers

    private func makeDate(_ yyyymmdd: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyymmdd) ?? Date()
    }
}
