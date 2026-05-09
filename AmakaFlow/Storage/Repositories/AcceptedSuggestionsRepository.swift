//
//  AcceptedSuggestionsRepository.swift
//  AmakaFlow
//

import Foundation
import GRDB

nonisolated final class AcceptedSuggestionsRepository {
    private let dbQueue: DatabaseQueue
    private let syncQueue: SyncQueueRepository
    private let now: () -> Date

    init(database: AppDatabase = .shared, syncQueue: SyncQueueRepository? = nil, now: @escaping () -> Date = Date.init) {
        self.dbQueue = database.dbQueue
        self.syncQueue = syncQueue ?? SyncQueueRepository(database: database, now: now)
        self.now = now
    }

    @discardableResult
    func insert(_ suggestion: LocalAcceptedSuggestion, enqueueSync: Bool = true) throws -> LocalAcceptedSuggestion {
        var record = suggestion
        try dbQueue.write { db in
            try record.upsert(db)
            if enqueueSync {
                try syncQueue.enqueue(in: db, resourceType: LocalAcceptedSuggestion.databaseTableName, resourceId: record.id, op: "upsert", payload: try encode(record))
            }
        }
        return record
    }

    /// AMA-1792 (CR pass 2): atomic accept-with-event. The pair
    /// (`accepted_suggestions` + matching `workout_events`) must land or
    /// roll back together — otherwise a half-applied write leaves an
    /// orphan event row that `hydrateIncoming` can resurrect on the next
    /// launch despite the canonical `accepted_suggestions` row never
    /// existing. Both upserts and both sync_queue enqueues happen inside
    /// one `dbQueue.write` transaction.
    func acceptedWithEvent(suggestion: LocalAcceptedSuggestion, event: LocalWorkoutEvent, enqueueSync: Bool = true) throws {
        var sg = suggestion
        var ev = event
        try dbQueue.write { db in
            // FK: accepted_suggestions.workout_event_id → workout_events.id.
            try ev.upsert(db)
            try sg.upsert(db)
            if enqueueSync {
                try syncQueue.enqueue(in: db, resourceType: LocalWorkoutEvent.databaseTableName, resourceId: ev.id, op: "upsert", payload: try encode(ev))
                try syncQueue.enqueue(in: db, resourceType: LocalAcceptedSuggestion.databaseTableName, resourceId: sg.id, op: "upsert", payload: try encode(sg))
            }
        }
    }

    func pendingForUser(_ userId: String) throws -> [LocalAcceptedSuggestion] {
        try dbQueue.read { db in
            try LocalAcceptedSuggestion
                .filter(LocalAcceptedSuggestion.Columns.userId == userId && LocalAcceptedSuggestion.Columns.deletedAt == nil && LocalAcceptedSuggestion.Columns.status == "accepted")
                .order(LocalAcceptedSuggestion.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func allForUser(_ userId: String) throws -> [LocalAcceptedSuggestion] {
        try dbQueue.read { db in
            try LocalAcceptedSuggestion
                .filter(LocalAcceptedSuggestion.Columns.userId == userId)
                .order(LocalAcceptedSuggestion.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func tombstone(id: String, enqueueSync: Bool = true) throws {
        let timestamp = now()
        try dbQueue.write { db in
            guard var record = try LocalAcceptedSuggestion.fetchOne(db, key: id) else { return }
            record.status = "deleted"
            record.deletedAt = timestamp
            record.updatedAt = timestamp
            try record.update(db)
            if enqueueSync {
                try syncQueue.enqueue(in: db, resourceType: LocalAcceptedSuggestion.databaseTableName, resourceId: id, op: "delete", payload: try encode(record))
            }
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        try encodeToJSONString(value)
    }
}
