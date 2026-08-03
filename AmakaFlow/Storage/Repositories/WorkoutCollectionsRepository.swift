//
//  WorkoutCollectionsRepository.swift
//  AmakaFlow
//
//  AMA-2376: local-first workout collections and pins.
//  Local-only by design — no sync_queue enqueue for any operation here.
//

import Foundation
import GRDB

nonisolated final class WorkoutCollectionsRepository {
    private let dbQueue: DatabaseQueue
    private let now: () -> Date

    init(database: AppDatabase = .shared, now: @escaping () -> Date = Date.init) {
        self.dbQueue = database.dbQueue
        self.now = now
    }

    @discardableResult
    func createCollection(name: String, note: String?) throws -> LocalWorkoutCollection {
        let timestamp = now()
        var record = LocalWorkoutCollection(
            id: UUID().uuidString,
            name: name,
            note: note,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try dbQueue.write { db in
            try record.insert(db)
        }
        return record
    }

    func renameCollection(id: String, name: String, note: String?) throws {
        try dbQueue.write { db in
            guard var record = try LocalWorkoutCollection.fetchOne(db, key: id) else { return }
            record.name = name
            record.note = note
            record.updatedAt = self.now()
            try record.update(db)
        }
    }

    func deleteCollection(id: String) throws {
        try dbQueue.write { db in
            // Members cascade via the FK's `onDelete: .cascade` (V3WorkoutCollections migration).
            _ = try LocalWorkoutCollection.deleteOne(db, key: id)
        }
    }

    func listCollections() throws -> [LocalWorkoutCollection] {
        try dbQueue.read { db in
            try LocalWorkoutCollection
                .order(LocalWorkoutCollection.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    func addMember(collectionId: String, workoutId: String) throws {
        try dbQueue.write { db in
            let alreadyMember = try LocalWorkoutCollectionMember
                .filter(LocalWorkoutCollectionMember.Columns.collectionId == collectionId
                    && LocalWorkoutCollectionMember.Columns.workoutId == workoutId)
                .fetchCount(db) > 0
            if alreadyMember {
                return
            }
            let nextPosition = try Int.fetchOne(db, sql: """
                SELECT COALESCE(MAX(position), 0) + 1 FROM workout_collection_members
                WHERE collection_id = ?
                """, arguments: [collectionId]) ?? 1
            var member = LocalWorkoutCollectionMember(collectionId: collectionId, workoutId: workoutId, position: nextPosition)
            try member.insert(db)
            try self.touchCollection(collectionId, db: db)
        }
    }

    func removeMember(collectionId: String, workoutId: String) throws {
        try dbQueue.write { db in
            _ = try LocalWorkoutCollectionMember
                .filter(LocalWorkoutCollectionMember.Columns.collectionId == collectionId
                    && LocalWorkoutCollectionMember.Columns.workoutId == workoutId)
                .deleteAll(db)
            try self.touchCollection(collectionId, db: db)
        }
    }

    func moveMembers(workoutIds: [String], from: String, to: String) throws {
        try dbQueue.write { db in
            for workoutId in workoutIds {
                _ = try LocalWorkoutCollectionMember
                    .filter(LocalWorkoutCollectionMember.Columns.collectionId == from
                        && LocalWorkoutCollectionMember.Columns.workoutId == workoutId)
                    .deleteAll(db)

                let alreadyMember = try LocalWorkoutCollectionMember
                    .filter(LocalWorkoutCollectionMember.Columns.collectionId == to
                        && LocalWorkoutCollectionMember.Columns.workoutId == workoutId)
                    .fetchCount(db) > 0
                if !alreadyMember {
                    let nextPosition = try Int.fetchOne(db, sql: """
                        SELECT COALESCE(MAX(position), 0) + 1 FROM workout_collection_members
                        WHERE collection_id = ?
                        """, arguments: [to]) ?? 1
                    var member = LocalWorkoutCollectionMember(collectionId: to, workoutId: workoutId, position: nextPosition)
                    try member.insert(db)
                }
            }
            try self.touchCollection(from, db: db)
            try self.touchCollection(to, db: db)
        }
    }

    func memberWorkoutIds(collectionId: String) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT workout_id FROM workout_collection_members
                WHERE collection_id = ? ORDER BY position ASC
                """, arguments: [collectionId])
        }
    }

    func collectionIds(containing workoutId: String) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT collection_id FROM workout_collection_members
                WHERE workout_id = ?
                """, arguments: [workoutId])
        }
    }

    func uncategorizedWorkoutIds(from knownWorkoutIds: Set<String>) throws -> [String] {
        try dbQueue.read { db in
            let memberWorkoutIds = try Set(String.fetchAll(db, sql: "SELECT DISTINCT workout_id FROM workout_collection_members"))
            return knownWorkoutIds.subtracting(memberWorkoutIds).sorted()
        }
    }

    func setPinned(workoutId: String, isPinned: Bool) throws {
        try dbQueue.write { db in
            if isPinned {
                var pin = LocalPinnedWorkout(workoutId: workoutId, pinnedAt: self.now())
                try pin.upsert(db)
            } else {
                _ = try LocalPinnedWorkout.deleteOne(db, key: workoutId)
            }
        }
    }

    func isPinned(workoutId: String) throws -> Bool {
        try dbQueue.read { db in
            try LocalPinnedWorkout.filter(key: workoutId).fetchCount(db) > 0
        }
    }

    func listPinnedWorkoutIds() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT workout_id FROM pinned_workouts ORDER BY pinned_at DESC")
        }
    }

    @discardableResult
    func pruneOrphans(knownWorkoutIds: Set<String>) throws -> Int {
        try dbQueue.write { db in
            var deleted = 0
            if knownWorkoutIds.isEmpty {
                deleted += try LocalWorkoutCollectionMember.deleteAll(db)
                deleted += try LocalPinnedWorkout.deleteAll(db)
            } else {
                let placeholders = knownWorkoutIds.map { _ in "?" }.joined(separator: ", ")
                let arguments = StatementArguments(Array(knownWorkoutIds))
                try db.execute(
                    sql: "DELETE FROM workout_collection_members WHERE workout_id NOT IN (\(placeholders))",
                    arguments: arguments
                )
                deleted += db.changesCount
                try db.execute(
                    sql: "DELETE FROM pinned_workouts WHERE workout_id NOT IN (\(placeholders))",
                    arguments: arguments
                )
                deleted += db.changesCount
            }
            return deleted
        }
    }

    private func touchCollection(_ collectionId: String, db: Database) throws {
        guard var collection = try LocalWorkoutCollection.fetchOne(db, key: collectionId) else { return }
        collection.updatedAt = now()
        try collection.update(db)
    }
}
