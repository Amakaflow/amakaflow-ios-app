//
//  V9_logbook.swift
//  AmakaFlow
//
//  AMA-2426: log drafts, per-set actuals rows, workout load plans (target pass).
//

import Foundation
import GRDB

enum V9Logbook {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v9_logbook") { database in
            try database.create(table: "log_drafts") { table in
                table.column("id", .text).primaryKey()
                table.column("workout_id", .text)
                table.column("title", .text).notNull()
                table.column("subtitle", .text).notNull().defaults(to: "")
                table.column("started_at", .datetime).notNull()
                table.column("last_edited_at", .datetime).notNull()
                table.column("state", .text).notNull()
                table.column("mode", .text).notNull()
                table.column("attached_session_id", .text)
                table.column("payload_json", .text).notNull()
                table.column("note", .text).notNull().defaults(to: "")
                table.column("rpe", .integer)
                table.column("reconciled_session_id", .text)
            }
            try database.create(
                index: "idx_log_drafts_state",
                on: "log_drafts",
                columns: ["state"]
            )
            try database.create(
                index: "idx_log_drafts_attached",
                on: "log_drafts",
                columns: ["attached_session_id"]
            )

            try database.create(table: "actuals_set_rows") { table in
                table.column("id", .text).primaryKey()
                table.column("exercise_row_id", .text).notNull()
                    .references("actuals_exercise_rows", onDelete: .cascade)
                table.column("set_index", .integer).notNull()
                table.column("is_warmup", .boolean).notNull().defaults(to: false)
                table.column("weight_kg", .double)
                table.column("reps", .integer)
                table.column("checked_at", .datetime)
            }
            try database.create(
                index: "idx_actuals_set_rows_exercise",
                on: "actuals_set_rows",
                columns: ["exercise_row_id", "set_index"]
            )

            try database.create(table: "workout_load_plans") { table in
                table.column("id", .text).primaryKey()
                table.column("workout_id", .text).notNull()
                table.column("exercise_key", .text).notNull()
                table.column("payload_json", .text).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try database.create(
                index: "idx_workout_load_plans_workout",
                on: "workout_load_plans",
                columns: ["workout_id", "exercise_key"],
                options: .unique
            )
        }
    }
}
