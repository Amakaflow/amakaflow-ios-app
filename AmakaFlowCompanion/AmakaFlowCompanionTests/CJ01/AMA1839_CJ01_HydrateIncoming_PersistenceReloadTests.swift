//
//  AMA1839_CJ01_HydrateIncoming_PersistenceReloadTests.swift
//  AmakaFlowCompanionTests
//
//  CJ-01 / L2 — Persistence reload: the Reopen step. After Save & End the
//  accepted_suggestion + workout_event rows must survive a fresh GRDB
//  connection on the same on-disk DB file (simulated force-quit + relaunch).
//
//  The view layer's `WorkoutsViewModel.hydrateIncoming` is fileprivate;
//  it filters todayPlan by `status == "planned"` and
//  `source == "suggestion_accepted"`. We exercise the same underlying
//  `WorkoutEventsRepository.todayPlan(...)` query (which is what
//  hydrateIncoming wraps) against a re-opened on-disk database — that
//  is the persistence contract CJ-01 actually depends on.
//

import XCTest
import GRDB
@testable import AmakaFlowCompanion

final class AMA1839_CJ01_HydrateIncoming_PersistenceReloadTests: XCTestCase {

    private let userId = "user-cj01-reopen"

    /// `WorkoutsViewModel.hydrateIncoming` filters to status==planned +
    /// source==suggestion_accepted + deletedAt==nil. Mirror that filter
    /// so the test asserts the same shape the home screen will see.
    private func hydrateLike(events: [LocalWorkoutEvent]) -> [LocalWorkoutEvent] {
        events.filter { $0.deletedAt == nil && $0.status == "planned" && $0.source == "suggestion_accepted" }
    }

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("amakaflow-cj01-reopen-\(UUID().uuidString).sqlite")
            .path
    }

    private func cleanup(_ path: String) {
        let fm = FileManager.default
        try? fm.removeItem(atPath: path)
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    private func makePair(date: String, timestamp: Date) -> (LocalAcceptedSuggestion, LocalWorkoutEvent) {
        let event = LocalWorkoutEvent(
            id: "evt-reopen-1",
            userId: userId,
            date: date,
            startTime: "07:00",
            endTime: "07:30",
            status: "planned",
            source: "suggestion_accepted",
            jsonPayload: #"{"id":"workout-reopen-1","name":"CJ-01 Reopen Workout"}"#,
            clientGeneratedId: "cgid-evt-reopen",
            serverVersion: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )
        let suggestion = LocalAcceptedSuggestion(
            id: "sugg-reopen-1",
            userId: userId,
            suggestionId: nil,
            workoutEventId: event.id,
            status: "accepted",
            clientGeneratedId: "cgid-sugg-reopen",
            serverVersion: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )
        return (suggestion, event)
    }

    private func dayString(_ date: Date) -> String {
        WorkoutEventsRepository.dayString(date)
    }

    // MARK: - Tests

    func test_hydrateIncoming__afterForceQuitRelaunch__returnsAcceptedWorkout() throws {
        let path = tempPath()
        defer { cleanup(path) }

        let timestamp = Date()
        let dayKey = dayString(timestamp)

        // === Session 1: Accept + Save (Generate → Save & End) ===
        do {
            let database = try AppDatabase(path: path)
            let suggestionsRepo = AcceptedSuggestionsRepository(database: database, now: { timestamp })
            let (suggestion, event) = makePair(date: dayKey, timestamp: timestamp)
            try suggestionsRepo.replacePriorAcceptsAndInsert(userId: userId, suggestion: suggestion, event: event, enqueueSync: false)
        }

        // === Simulated force-quit: drop the AppDatabase reference, reopen
        //     a fresh instance against the same on-disk file ===
        let reopened = try AppDatabase(path: path)
        let eventsRepo = WorkoutEventsRepository(database: reopened, now: { timestamp })

        let events = try eventsRepo.todayPlan(userId: userId, date: timestamp)
        let hydrated = hydrateLike(events: events)

        XCTAssertEqual(hydrated.count, 1,
                       "after force-quit + relaunch, hydrateIncoming-equivalent query must return the accepted workout (CJ-01 Reopen step)")
        let row = try XCTUnwrap(hydrated.first, "hydrated event row must be present")
        XCTAssertEqual(row.id, "evt-reopen-1", "the persisted workout_event id must round-trip across the reopen")
        XCTAssertEqual(row.source, "suggestion_accepted", "row source must remain suggestion_accepted so WorkoutsViewModel.hydrateIncoming surfaces it")
        XCTAssertEqual(row.status, "planned", "row status must remain planned across the reopen")
        XCTAssertTrue(row.jsonPayload.contains("CJ-01 Reopen Workout"), "json_payload (decoded into Workout struct by hydrateIncoming) must round-trip")
    }

    func test_hydrateIncoming__rowTombstonedBeforeRelaunch__returnsEmptyAfterReopen() throws {
        let path = tempPath()
        defer { cleanup(path) }

        let timestamp = Date()
        let dayKey = dayString(timestamp)

        // Session 1: write the pair, then tombstone the workout_event
        // (mirrors WorkoutsViewModel.tombstoneLocalSuggestion on schedule/complete).
        do {
            let database = try AppDatabase(path: path)
            let suggestionsRepo = AcceptedSuggestionsRepository(database: database, now: { timestamp })
            let eventsRepo = WorkoutEventsRepository(database: database, now: { timestamp })
            let (suggestion, event) = makePair(date: dayKey, timestamp: timestamp)
            try suggestionsRepo.replacePriorAcceptsAndInsert(userId: userId, suggestion: suggestion, event: event, enqueueSync: false)
            try eventsRepo.tombstone(id: event.id, enqueueSync: false)
        }

        // Session 2: reopen.
        let reopened = try AppDatabase(path: path)
        let eventsRepo = WorkoutEventsRepository(database: reopened, now: { timestamp })

        let events = try eventsRepo.todayPlan(userId: userId, date: timestamp)
        let hydrated = hydrateLike(events: events)

        XCTAssertEqual(hydrated.count, 0,
                       "tombstoned workout_event must NOT resurface after reopen — guards against the AMA-1792 ghost-row regression")
    }

    func test_hydrateIncoming__missingUserId__returnsEmpty() throws {
        let path = tempPath()
        defer { cleanup(path) }

        let database = try AppDatabase(path: path)
        let eventsRepo = WorkoutEventsRepository(database: database, now: { Date() })

        // No data written: a fresh-install / pre-auth launch should not
        // throw and should return an empty list (matches hydrateIncoming
        // pre-auth contract: "show nothing rather than leaking another user's data").
        let events = try eventsRepo.todayPlan(userId: userId, date: Date())
        XCTAssertEqual(events.count, 0, "fresh on-disk DB must yield zero today-plan events for any user")
    }
}
