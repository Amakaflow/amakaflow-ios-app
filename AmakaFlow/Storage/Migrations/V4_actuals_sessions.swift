//
//  V4_actuals_sessions.swift
//  AmakaFlow
//
//  AMA-2387: local-first fill-in actuals sessions + exercise rows.
//

import Foundation
import GRDB

enum V4ActualsSessions {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4_actuals_sessions") { database in
            try database.create(table: "actuals_sessions") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("subtitle", .text).notNull()
                table.column("rpe", .integer)
                table.column("verified", .boolean).notNull().defaults(to: false)
                table.column("saved_at", .datetime).notNull()
                table.column("created_at", .datetime).notNull()
            }
            try database.create(table: "actuals_exercise_rows") { table in
                table.column("id", .text).primaryKey()
                table.column("session_id", .text).notNull()
                    .references("actuals_sessions", onDelete: .cascade)
                table.column("exercise_key", .text).notNull()
                table.column("name", .text).notNull()
                table.column("planned_sets", .integer).notNull()
                table.column("planned_reps", .integer).notNull()
                table.column("planned_weight_kg", .double)
                table.column("planned_note", .text)
                table.column("confirmation", .text).notNull()
                table.column("actual_sets", .integer).notNull()
                table.column("actual_reps", .integer).notNull()
                table.column("actual_weight_kg", .double)
                table.column("position", .integer).notNull()
            }
            try database.create(
                index: "idx_actuals_exercise_rows_session",
                on: "actuals_exercise_rows",
                columns: ["session_id"]
            )
        }
    }
}
