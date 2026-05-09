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
        var mutableSuggestion = suggestion
        var mutableEvent = event
        try dbQueue.write { db in
            // FK: accepted_suggestions.workout_event_id → workout_events.id.
            try mutableEvent.upsert(db)
            try mutableSuggestion.upsert(db)
            if enqueueSync {
                try syncQueue.enqueue(in: db, resourceType: LocalWorkoutEvent.databaseTableName, resourceId: mutableEvent.id, op: "upsert", payload: try encode(mutableEvent))
                try syncQueue.enqueue(in: db, resourceType: LocalAcceptedSuggestion.databaseTableName, resourceId: mutableSuggestion.id, op: "upsert", payload: try encode(mutableSuggestion))
            }
        }
    }

    /// AMA-1815: "replace on accept" — in a single transaction, tombstone
    /// every live accepted-suggestion + workout_event for `userId`, then
    /// insert the new pair. Restores the old user-perceived contract that
    /// each Suggest → Accept supersedes the previous one (Quick Start +
    /// Today now show ONE accepted suggestion at a time, not the
    /// accumulated history surfaced by the AMA-1792 GRDB rewire).
    ///
    /// Sync queue gets a `delete` enqueue per superseded row + an `upsert`
    /// for the new pair so the backend stays consistent.
    func replacePriorAcceptsAndInsert(userId: String, suggestion: LocalAcceptedSuggestion, event: LocalWorkoutEvent, enqueueSync: Bool = true) throws {
        // CR: invariant guard. Without it a mismatched `userId` arg would
        // tombstone one user's live rows in the same transaction that
        // inserts another user's pair — silent cross-user data corruption.
        guard suggestion.userId == userId,
              event.userId == userId,
              suggestion.workoutEventId == event.id else {
            throw NSError(
                domain: "AcceptedSuggestionsRepository",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "replacePriorAcceptsAndInsert invariant: suggestion/event must belong to userId and pair via workout_event_id"]
            )
        }
        let timestamp = now()
        var newSuggestion = suggestion
        var newEvent = event
        try dbQueue.write { db in
            // 1. Tombstone every live accepted_suggestion for this user
            //    (and its matching workout_event) so the new accept is the
            //    only suggestion-accepted row hydrateIncoming returns.
            let live = try LocalAcceptedSuggestion
                .filter(LocalAcceptedSuggestion.Columns.userId == userId
                    && LocalAcceptedSuggestion.Columns.deletedAt == nil
                    && LocalAcceptedSuggestion.Columns.status == "accepted"
                    && LocalAcceptedSuggestion.Columns.id != newSuggestion.id)
                .fetchAll(db)
            for var prior in live {
                prior.status = "deleted"
                prior.deletedAt = timestamp
                prior.updatedAt = timestamp
                try prior.update(db)
                if enqueueSync {
                    try syncQueue.enqueue(in: db, resourceType: LocalAcceptedSuggestion.databaseTableName, resourceId: prior.id, op: "delete", payload: try encode(prior))
                }
                // CR: tombstone the workout_event via the FK
                // (`workoutEventId`) not the suggestion's own id. Today
                // they happen to match but the schema allows divergence.
                if let priorEventId = prior.workoutEventId,
                   var priorEvent = try LocalWorkoutEvent.fetchOne(db, key: priorEventId),
                   priorEvent.deletedAt == nil {
                    priorEvent.deletedAt = timestamp
                    priorEvent.updatedAt = timestamp
                    try priorEvent.update(db)
                    if enqueueSync {
                        try syncQueue.enqueue(in: db, resourceType: LocalWorkoutEvent.databaseTableName, resourceId: priorEvent.id, op: "delete", payload: try encode(priorEvent))
                    }
                }
            }

            // 2. FK: workout_events.id must exist before accepted_suggestions.workout_event_id.
            try newEvent.upsert(db)
            try newSuggestion.upsert(db)
            if enqueueSync {
                try syncQueue.enqueue(in: db, resourceType: LocalWorkoutEvent.databaseTableName, resourceId: newEvent.id, op: "upsert", payload: try encode(newEvent))
                try syncQueue.enqueue(in: db, resourceType: LocalAcceptedSuggestion.databaseTableName, resourceId: newSuggestion.id, op: "upsert", payload: try encode(newSuggestion))
            }
        }
    }

    /// AMA-1792 (CR pass 3): atomic tombstone for the accept pair. Mirrors
    /// `acceptedWithEvent` so a complete-or-schedule never leaves one row
    /// soft-deleted while the other stays live (which would let
    /// `hydrateIncoming` resurrect the workout). Both writes and both
    /// sync_queue deletes commit together or roll back together.
    func tombstoneWithEvent(id: String, enqueueSync: Bool = true) throws {
        let timestamp = now()
        try dbQueue.write { db in
            if var suggestion = try LocalAcceptedSuggestion.fetchOne(db, key: id) {
                suggestion.status = "deleted"
                suggestion.deletedAt = timestamp
                suggestion.updatedAt = timestamp
                try suggestion.update(db)
                if enqueueSync {
                    try syncQueue.enqueue(in: db, resourceType: LocalAcceptedSuggestion.databaseTableName, resourceId: id, op: "delete", payload: try encode(suggestion))
                }
            }
            if var event = try LocalWorkoutEvent.fetchOne(db, key: id) {
                event.deletedAt = timestamp
                event.updatedAt = timestamp
                try event.update(db)
                if enqueueSync {
                    try syncQueue.enqueue(in: db, resourceType: LocalWorkoutEvent.databaseTableName, resourceId: id, op: "delete", payload: try encode(event))
                }
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
