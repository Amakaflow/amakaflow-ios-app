//
//  WorkoutEventsRepository.swift
//  AmakaFlow
//

import Foundation
import GRDB

final class WorkoutEventsRepository {
    private let dbQueue: DatabaseQueue
    private let syncQueue: SyncQueueRepository
    private let now: () -> Date

    init(database: AppDatabase = .shared, syncQueue: SyncQueueRepository? = nil, now: @escaping () -> Date = Date.init) {
        self.dbQueue = database.dbQueue
        self.syncQueue = syncQueue ?? SyncQueueRepository(database: database, now: now)
        self.now = now
    }

    @discardableResult
    func upsert(_ event: LocalWorkoutEvent, enqueueSync: Bool = true) throws -> LocalWorkoutEvent {
        var record = event
        try dbQueue.write { db in
            try record.save(db)
        }
        if enqueueSync {
            try syncQueue.enqueue(resourceType: LocalWorkoutEvent.databaseTableName, resourceId: record.id, op: "upsert", payload: try encode(record))
        }
        return record
    }

    func eventsForUser(_ userId: String, from startDate: String, to endDate: String) throws -> [LocalWorkoutEvent] {
        try dbQueue.read { db in
            try LocalWorkoutEvent
                .filter(LocalWorkoutEvent.Columns.userId == userId && LocalWorkoutEvent.Columns.date >= startDate && LocalWorkoutEvent.Columns.date <= endDate && LocalWorkoutEvent.Columns.deletedAt == nil)
                .order(LocalWorkoutEvent.Columns.date.asc, LocalWorkoutEvent.Columns.startTime.asc, LocalWorkoutEvent.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func todayPlan(userId: String, date: Date = Date(), calendar: Calendar = .current) throws -> [LocalWorkoutEvent] {
        try eventsForUser(userId, from: Self.dayString(date, calendar: calendar), to: Self.dayString(date, calendar: calendar))
    }

    func tombstone(id: String, enqueueSync: Bool = true) throws {
        let timestamp = now()
        var updated: LocalWorkoutEvent?
        try dbQueue.write { db in
            guard var record = try LocalWorkoutEvent.fetchOne(db, key: id) else { return }
            record.deletedAt = timestamp
            record.updatedAt = timestamp
            try record.update(db)
            updated = record
        }
        if enqueueSync, let updated {
            try syncQueue.enqueue(resourceType: LocalWorkoutEvent.databaseTableName, resourceId: id, op: "delete", payload: try encode(updated))
        }
    }

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        var formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}
