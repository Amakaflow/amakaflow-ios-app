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
        migrator.registerMigration("v3_workout_collections") { database in
            try database.create(table: "workout_collections") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("note", .text)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try database.create(table: "workout_collection_members") { table in
                table.column("collection_id", .text).notNull()
                    .references("workout_collections", onDelete: .cascade)
                table.column("workout_id", .text).notNull()
                table.column("position", .integer).notNull()
                table.primaryKey(["collection_id", "workout_id"])
            }
            try database.create(
                index: "idx_workout_collection_members_workout",
                on: "workout_collection_members",
                columns: ["workout_id"]
            )
            try database.create(table: "pinned_workouts") { table in
                table.column("workout_id", .text).primaryKey()
                table.column("pinned_at", .datetime).notNull()
            }
            // Intentionally no context_label — derive at render.
        }
    }
}
