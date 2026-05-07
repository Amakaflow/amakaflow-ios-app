//
//  AcceptedSuggestionsRepository.swift
//  AmakaFlow
//

import Foundation
import GRDB

final class AcceptedSuggestionsRepository {
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
            try record.save(db)
            if enqueueSync {
                try syncQueue.enqueue(in: db, resourceType: LocalAcceptedSuggestion.databaseTableName, resourceId: record.id, op: "upsert", payload: try encode(record))
            }
        }
        return record
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}
