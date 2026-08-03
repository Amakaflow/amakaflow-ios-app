//
//  V3_workout_collections.swift
//  AmakaFlow
//
//  AMA-2376: local-first workout collections and pins.
//

import Foundation
import GRDB

enum V3WorkoutCollections {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_workout_collections") { db in
            try db.create(table: "workout_collections") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("note", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "workout_collection_members") { t in
                t.column("collection_id", .text).notNull()
                    .references("workout_collections", onDelete: .cascade)
                t.column("workout_id", .text).notNull()
                t.column("position", .integer).notNull()
                t.primaryKey(["collection_id", "workout_id"])
            }
            try db.create(
                index: "idx_workout_collection_members_workout",
                on: "workout_collection_members",
                columns: ["workout_id"]
            )
            try db.create(table: "pinned_workouts") { t in
                t.column("workout_id", .text).primaryKey()
                t.column("pinned_at", .datetime).notNull()
            }
            // Intentionally no context_label — derive at render.
        }
    }
}
