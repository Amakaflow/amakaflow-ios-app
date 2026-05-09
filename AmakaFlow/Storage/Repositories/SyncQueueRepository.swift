//
//  SyncQueueRepository.swift
//  AmakaFlow
//

import Foundation
import GRDB

nonisolated final class SyncQueueRepository {
    private let dbQueue: DatabaseQueue
    private let now: () -> Date

    init(database: AppDatabase = .shared, now: @escaping () -> Date = Date.init) {
        self.dbQueue = database.dbQueue
        self.now = now
    }

    @discardableResult
    func enqueue(resourceType: String, resourceId: String, op: String, payload: String, id: String = UUID().uuidString) throws -> SyncQueueItem {
        try dbQueue.write { db in
            try enqueue(in: db, resourceType: resourceType, resourceId: resourceId, op: op, payload: payload, id: id)
        }
    }

    @discardableResult
    func enqueue(in db: Database, resourceType: String, resourceId: String, op: String, payload: String, id: String = UUID().uuidString) throws -> SyncQueueItem {
        let timestamp = now()
        var item = SyncQueueItem(
            id: id,
            resourceType: resourceType,
            resourceId: resourceId,
            op: op,
            payload: payload,
            attemptCount: 0,
            lastAttemptedAt: nil,
            nextAttemptAt: timestamp,
            errorReason: nil,
            status: .pending,
            createdAt: timestamp,
            updatedAt: timestamp,
            requestId: nil
        )
        try item.insert(db)
        return item
    }

    /// AMA-1823: stamp a fresh request_id on the queue row at the start of
    /// each sync attempt. A retry generates a new ID, so this is the only
    /// path that updates the column after enqueue. Touches `updated_at` to
    /// keep the audit trail consistent with the other state mutators.
    func updateRequestId(_ id: String, requestId: String) throws {
        try dbQueue.write { db in
            guard var item = try SyncQueueItem.fetchOne(db, key: id) else { return }
            item.requestId = requestId
            item.updatedAt = now()
            try item.update(db)
        }
    }

    func pending(limit: Int = 25) throws -> [SyncQueueItem] {
        let timestamp = now()
        return try dbQueue.read { db in
            try SyncQueueItem.fetchAll(
                db,
                sql: """
                SELECT * FROM sync_queue
                WHERE status IN (?, ?)
                  AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
                ORDER BY created_at ASC
                LIMIT ?
                """,
                arguments: [
                    SyncQueueStatus.pending.rawValue,
                    SyncQueueStatus.failed.rawValue,
                    timestamp,
                    limit
                ]
            )
        }
    }

    func markInFlight(_ id: String) throws {
        try update(id: id, status: .inFlight, errorReason: nil, nextAttemptAt: nil, incrementAttempt: false, recordAttempt: true)
    }

    func markSynced(_ id: String) throws {
        try update(id: id, status: .synced, errorReason: nil, nextAttemptAt: nil, incrementAttempt: false, recordAttempt: true)
    }

    func markFailed(_ id: String, error: String, retryAfter: TimeInterval, poisonAfter maxAttempts: Int) throws {
        try dbQueue.write { db in
            guard var item = try SyncQueueItem.fetchOne(db, key: id) else { return }
            let timestamp = now()
            item.attemptCount += 1
            item.lastAttemptedAt = timestamp
            item.nextAttemptAt = timestamp.addingTimeInterval(retryAfter)
            item.errorReason = error
            item.status = item.attemptCount >= maxAttempts ? .poison : .failed
            item.updatedAt = timestamp
            try item.update(db)
        }
    }

    @discardableResult
    func deleteSynced(olderThan retention: TimeInterval) throws -> Int {
        try deleteOlderThan(statuses: [.synced], olderThan: now().addingTimeInterval(-retention))
    }

    @discardableResult
    func deleteCompleted(olderThan retention: TimeInterval) throws -> Int {
        try deleteOlderThan(statuses: [.synced, .poison], olderThan: now().addingTimeInterval(-retention))
    }

    @discardableResult
    func deleteOlderThan(statuses: [SyncQueueStatus], olderThan cutoff: Date) throws -> Int {
        guard !statuses.isEmpty else { return 0 }
        let placeholders = statuses.map { _ in "?" }.joined(separator: ", ")
        return try dbQueue.write { db in
            var arguments = StatementArguments(statuses.map(\.rawValue))
            arguments += [cutoff]
            try db.execute(
                sql: "DELETE FROM sync_queue WHERE status IN (\(placeholders)) AND updated_at <= ?",
                arguments: arguments
            )
            return db.changesCount
        }
    }

    func summary() throws -> SyncQueueSummary {
        try dbQueue.read { db in
            let pending = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?", arguments: [SyncQueueStatus.pending.rawValue]) ?? 0
            let inFlight = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?", arguments: [SyncQueueStatus.inFlight.rawValue]) ?? 0
            let failed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?", arguments: [SyncQueueStatus.failed.rawValue]) ?? 0
            let poison = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE status = ?", arguments: [SyncQueueStatus.poison.rawValue]) ?? 0
            let lastAttempt = try Date.fetchOne(db, sql: "SELECT MAX(last_attempted_at) FROM sync_queue")
            let latestError = try String.fetchOne(db, sql: "SELECT error_reason FROM sync_queue WHERE error_reason IS NOT NULL ORDER BY updated_at DESC LIMIT 1")
            return SyncQueueSummary(pendingCount: pending, inFlightCount: inFlight, failedCount: failed, poisonCount: poison, lastAttemptedAt: lastAttempt, latestError: latestError)
        }
    }

    private func update(id: String, status: SyncQueueStatus, errorReason: String?, nextAttemptAt: Date?, incrementAttempt: Bool, recordAttempt: Bool = false) throws {
        try dbQueue.write { db in
            guard var item = try SyncQueueItem.fetchOne(db, key: id) else { return }
            let timestamp = now()
            item.status = status
            item.errorReason = errorReason
            item.nextAttemptAt = nextAttemptAt
            item.updatedAt = timestamp
            if recordAttempt { item.lastAttemptedAt = timestamp }
            if incrementAttempt { item.attemptCount += 1 }
            try item.update(db)
        }
    }
}
