//
//  V1_initial_schema.swift
//  AmakaFlow
//

import Foundation
import GRDB

enum V1InitialSchema {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial_local_first_schema") { db in
            try createAIRuns(db)
            try createWorkoutEvents(db)
            try createAcceptedSuggestions(db)
            try createSyncQueue(db)
        }
    }

    private static func createAIRuns(_ db: Database) throws {
        try db.create(table: "ai_runs", ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("user_id", .text).notNull().indexed()
            table.column("kind", .text).notNull()
            table.column("prompt_version", .text).notNull()
            table.column("model", .text).notNull()
            table.column("input", .text).notNull()
            table.column("output", .text).notNull()
            table.column("latency_ms", .integer)
            table.column("input_tokens", .integer)
            table.column("output_tokens", .integer)
            table.column("cost_usd", .double)
            table.column("created_at", .datetime).notNull()
        }
        try db.create(index: "idx_ai_runs_user_kind_created", on: "ai_runs", columns: ["user_id", "kind", "created_at"], ifNotExists: true)
    }

    private static func createWorkoutEvents(_ db: Database) throws {
        try db.create(table: "workout_events", ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("user_id", .text).notNull().indexed()
            table.column("date", .text).notNull()
            table.column("start_time", .text)
            table.column("end_time", .text)
            table.column("status", .text).notNull()
            table.column("source", .text)
            table.column("json_payload", .text).notNull()
            table.column("client_generated_id", .text).notNull()
            table.column("server_version", .integer).notNull().defaults(to: 1)
            table.column("created_at", .datetime).notNull()
            table.column("updated_at", .datetime).notNull()
            table.column("deleted_at", .datetime)
        }
        try db.create(index: "idx_workout_events_user_date", on: "workout_events", columns: ["user_id", "date"], ifNotExists: true)
        try db.create(index: "idx_workout_events_user_client_id", on: "workout_events", columns: ["user_id", "client_generated_id"], unique: true, ifNotExists: true)
    }

    private static func createAcceptedSuggestions(_ db: Database) throws {
        try db.create(table: "accepted_suggestions", ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("user_id", .text).notNull().indexed()
            table.column("suggestion_id", .text).references("ai_runs", onDelete: .setNull)
            table.column("workout_event_id", .text).references("workout_events", onDelete: .setNull)
            table.column("status", .text).notNull()
            table.column("client_generated_id", .text).notNull()
            table.column("server_version", .integer).notNull().defaults(to: 1)
            table.column("created_at", .datetime).notNull()
            table.column("updated_at", .datetime).notNull()
            table.column("deleted_at", .datetime)
        }
        try db.create(index: "idx_accepted_suggestions_user_status_created", on: "accepted_suggestions", columns: ["user_id", "status", "created_at"], ifNotExists: true)
        try db.create(index: "idx_accepted_suggestions_user_client_id", on: "accepted_suggestions", columns: ["user_id", "client_generated_id"], unique: true, ifNotExists: true)
    }

    private static func createSyncQueue(_ db: Database) throws {
        try db.create(table: "sync_queue", ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("resource_type", .text).notNull()
            table.column("resource_id", .text).notNull()
            table.column("op", .text).notNull()
            table.column("payload", .text).notNull()
            table.column("attempt_count", .integer).notNull().defaults(to: 0)
            table.column("last_attempted_at", .datetime)
            table.column("next_attempt_at", .datetime)
            table.column("error_reason", .text)
            table.column("status", .text).notNull().defaults(to: "pending")
            table.column("created_at", .datetime).notNull()
            table.column("updated_at", .datetime).notNull()
            table.check(sql: "status IN ('pending','in_flight','synced','failed','poison')")
        }
        try db.create(index: "idx_sync_queue_status_next_attempt", on: "sync_queue", columns: ["status", "next_attempt_at", "created_at"], ifNotExists: true)
        try db.create(index: "idx_sync_queue_resource", on: "sync_queue", columns: ["resource_type", "resource_id"], ifNotExists: true)
    }
}
