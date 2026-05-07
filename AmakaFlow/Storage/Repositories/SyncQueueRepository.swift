//
//  SyncQueueRepository.swift
//  AmakaFlow
//

import Foundation
import GRDB

final class SyncQueueRepository {
    private let dbQueue: DatabaseQueue
    private let now: () -> Date

    init(database: AppDatabase = .shared, now: @escaping () -> Date = Date.init) {
        self.dbQueue = database.dbQueue
        self.now = now
    }

    @discardableResult
    func enqueue(resourceType: String, resourceId: String, op: String, payload: String, id: String = UUID().uuidString) throws -> SyncQueueItem {
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
            status: SyncQueueStatus.pending.rawValue,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try dbQueue.write { db in try item.insert(db) }
        return item
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
        try update(id: id, status: .inFlight, errorReason: nil, nextAttemptAt: nil, incrementAttempt: false)
    }

    func markSynced(_ id: String) throws {
        try update(id: id, status: .synced, errorReason: nil, nextAttemptAt: nil, incrementAttempt: false)
    }

    func markFailed(_ id: String, error: String, retryAfter: TimeInterval, poisonAfter maxAttempts: Int) throws {
        try dbQueue.write { db in
            guard var item = try SyncQueueItem.fetchOne(db, key: id) else { return }
            let timestamp = now()
            item.attemptCount += 1
            item.lastAttemptedAt = timestamp
            item.nextAttemptAt = timestamp.addingTimeInterval(retryAfter)
            item.errorReason = error
            item.status = item.attemptCount >= maxAttempts ? SyncQueueStatus.poison.rawValue : SyncQueueStatus.failed.rawValue
            item.updatedAt = timestamp
            try item.update(db)
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

    private func update(id: String, status: SyncQueueStatus, errorReason: String?, nextAttemptAt: Date?, incrementAttempt: Bool) throws {
        try dbQueue.write { db in
            guard var item = try SyncQueueItem.fetchOne(db, key: id) else { return }
            item.status = status.rawValue
            item.errorReason = errorReason
            item.nextAttemptAt = nextAttemptAt
            item.updatedAt = now()
            if incrementAttempt { item.attemptCount += 1 }
            try item.update(db)
        }
    }
}
