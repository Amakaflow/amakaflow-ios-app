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
        try dbQueue.write { database in
            try record.insert(database)
        }
        return record
    }

    func renameCollection(id: String, name: String, note: String?) throws {
        try dbQueue.write { database in
            guard var record = try LocalWorkoutCollection.fetchOne(database, key: id) else { return }
            record.name = name
            record.note = note
            record.updatedAt = self.now()
            try record.update(database)
        }
    }

    func deleteCollection(id: String) throws {
        try dbQueue.write { database in
            // Members cascade via the FK's `onDelete: .cascade` (V3WorkoutCollections migration).
            _ = try LocalWorkoutCollection.deleteOne(database, key: id)
        }
    }

    func listCollections() throws -> [LocalWorkoutCollection] {
        try dbQueue.read { database in
            try LocalWorkoutCollection
                .order(LocalWorkoutCollection.Columns.updatedAt.desc)
                .fetchAll(database)
        }
    }

    func addMember(collectionId: String, workoutId: String) throws {
        try dbQueue.write { database in
            try self.insertMemberIfNeeded(
                collectionId: collectionId,
                workoutId: workoutId,
                database: database
            )
            try self.touchCollection(collectionId, database: database)
        }
    }

    /// Inserts many members in one write transaction (single `touchCollection`).
    func addMembers(collectionId: String, workoutIds: [String]) throws {
        guard !workoutIds.isEmpty else { return }
        try dbQueue.write { database in
            for workoutId in workoutIds {
                try self.insertMemberIfNeeded(
                    collectionId: collectionId,
                    workoutId: workoutId,
                    database: database
                )
            }
            try self.touchCollection(collectionId, database: database)
        }
    }

    func removeMember(collectionId: String, workoutId: String) throws {
        try dbQueue.write { database in
            _ = try LocalWorkoutCollectionMember
                .filter(LocalWorkoutCollectionMember.Columns.collectionId == collectionId
                    && LocalWorkoutCollectionMember.Columns.workoutId == workoutId)
                .deleteAll(database)
            try self.touchCollection(collectionId, database: database)
        }
    }

    func moveMembers(workoutIds: [String], fromCollectionId: String, toCollectionId: String) throws {
        try dbQueue.write { database in
            for workoutId in workoutIds {
                _ = try LocalWorkoutCollectionMember
                    .filter(LocalWorkoutCollectionMember.Columns.collectionId == fromCollectionId
                        && LocalWorkoutCollectionMember.Columns.workoutId == workoutId)
                    .deleteAll(database)

                let alreadyMember = try LocalWorkoutCollectionMember
                    .filter(LocalWorkoutCollectionMember.Columns.collectionId == toCollectionId
                        && LocalWorkoutCollectionMember.Columns.workoutId == workoutId)
                    .fetchCount(database) > 0
                if !alreadyMember {
                    let nextPosition = try Int.fetchOne(database, sql: """
                        SELECT COALESCE(MAX(position), 0) + 1 FROM workout_collection_members
                        WHERE collection_id = ?
                        """, arguments: [toCollectionId]) ?? 1
                    var member = LocalWorkoutCollectionMember(collectionId: toCollectionId, workoutId: workoutId, position: nextPosition)
                    try member.insert(database)
                }
            }
            try self.touchCollection(fromCollectionId, database: database)
            try self.touchCollection(toCollectionId, database: database)
        }
    }

    func memberWorkoutIds(collectionId: String) throws -> [String] {
        try dbQueue.read { database in
            try String.fetchAll(database, sql: """
                SELECT workout_id FROM workout_collection_members
                WHERE collection_id = ? ORDER BY position ASC
                """, arguments: [collectionId])
        }
    }

    func collectionIds(containing workoutId: String) throws -> [String] {
        try dbQueue.read { database in
            try String.fetchAll(database, sql: """
                SELECT collection_id FROM workout_collection_members
                WHERE workout_id = ?
                """, arguments: [workoutId])
        }
    }

    func uncategorizedWorkoutIds(from knownWorkoutIds: Set<String>) throws -> [String] {
        try dbQueue.read { database in
            let memberWorkoutIds = try Set(String.fetchAll(database, sql: "SELECT DISTINCT workout_id FROM workout_collection_members"))
            return knownWorkoutIds.subtracting(memberWorkoutIds).sorted()
        }
    }

    func setPinned(workoutId: String, isPinned: Bool) throws {
        try dbQueue.write { database in
            if isPinned {
                var pin = LocalPinnedWorkout(workoutId: workoutId, pinnedAt: self.now())
                try pin.upsert(database)
            } else {
                _ = try LocalPinnedWorkout.deleteOne(database, key: workoutId)
            }
        }
    }

    func isPinned(workoutId: String) throws -> Bool {
        try dbQueue.read { database in
            try LocalPinnedWorkout.filter(key: workoutId).fetchCount(database) > 0
        }
    }

    func listPinnedWorkoutIds() throws -> [String] {
        try dbQueue.read { database in
            try String.fetchAll(database, sql: "SELECT workout_id FROM pinned_workouts ORDER BY pinned_at DESC")
        }
    }

    @discardableResult
    func pruneOrphans(knownWorkoutIds: Set<String>) throws -> Int {
        try dbQueue.write { database in
            var deleted = 0
            if knownWorkoutIds.isEmpty {
                deleted += try LocalWorkoutCollectionMember.deleteAll(database)
                deleted += try LocalPinnedWorkout.deleteAll(database)
            } else {
                let placeholders = knownWorkoutIds.map { _ in "?" }.joined(separator: ", ")
                let arguments = StatementArguments(Array(knownWorkoutIds))
                try database.execute(
                    sql: "DELETE FROM workout_collection_members WHERE workout_id NOT IN (\(placeholders))",
                    arguments: arguments
                )
                deleted += database.changesCount
                try database.execute(
                    sql: "DELETE FROM pinned_workouts WHERE workout_id NOT IN (\(placeholders))",
                    arguments: arguments
                )
                deleted += database.changesCount
            }
            return deleted
        }
    }

    private func insertMemberIfNeeded(
        collectionId: String,
        workoutId: String,
        database: Database
    ) throws {
        let alreadyMember = try LocalWorkoutCollectionMember
            .filter(LocalWorkoutCollectionMember.Columns.collectionId == collectionId
                && LocalWorkoutCollectionMember.Columns.workoutId == workoutId)
            .fetchCount(database) > 0
        if alreadyMember {
            return
        }
        let nextPosition = try Int.fetchOne(database, sql: """
            SELECT COALESCE(MAX(position), 0) + 1 FROM workout_collection_members
            WHERE collection_id = ?
            """, arguments: [collectionId]) ?? 1
        var member = LocalWorkoutCollectionMember(
            collectionId: collectionId,
            workoutId: workoutId,
            position: nextPosition
        )
        try member.insert(database)
    }

    private func touchCollection(_ collectionId: String, database: Database) throws {
        guard var collection = try LocalWorkoutCollection.fetchOne(database, key: collectionId) else { return }
        collection.updatedAt = now()
        try collection.update(database)
    }
}
