//
//  LocalRecords.swift
//  AmakaFlow
//

import Foundation
import GRDB

enum SyncQueueStatus: String, Codable, CaseIterable {
    case pending
    case inFlight = "in_flight"
    case synced
    case failed
    case poison
}

struct LocalAcceptedSuggestion: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "accepted_suggestions"
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: String
    var userId: String
    var suggestionId: String?
    var workoutEventId: String?
    var status: String
    var clientGeneratedId: String
    var serverVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum Columns: String, ColumnExpression {
        case id, userId = "user_id", suggestionId = "suggestion_id", workoutEventId = "workout_event_id"
        case status, clientGeneratedId = "client_generated_id", serverVersion = "server_version"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }
}

struct LocalWorkoutEvent: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "workout_events"
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: String
    var userId: String
    var date: String
    var startTime: String?
    var endTime: String?
    var status: String
    var source: String?
    var jsonPayload: String
    var clientGeneratedId: String
    var serverVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum Columns: String, ColumnExpression {
        case id, userId = "user_id", date, startTime = "start_time", endTime = "end_time"
        case status, source, jsonPayload = "json_payload", clientGeneratedId = "client_generated_id"
        case serverVersion = "server_version", createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }
}

struct LocalAIRun: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "ai_runs"
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: String
    var userId: String
    var kind: String
    var promptVersion: String
    var model: String
    var input: String
    var output: String
    var latencyMs: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var costUsd: Double?
    var createdAt: Date

    enum Columns: String, ColumnExpression {
        case id, userId = "user_id", kind, promptVersion = "prompt_version", model, input, output
        case latencyMs = "latency_ms", inputTokens = "input_tokens", outputTokens = "output_tokens"
        case costUsd = "cost_usd", createdAt = "created_at"
    }
}

struct SyncQueueItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "sync_queue"
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: String
    var resourceType: String
    var resourceId: String
    var op: String
    var payload: String
    var attemptCount: Int
    var lastAttemptedAt: Date?
    var nextAttemptAt: Date?
    var errorReason: String?
    var status: String
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, resourceType = "resource_type", resourceId = "resource_id", op, payload
        case attemptCount = "attempt_count", lastAttemptedAt = "last_attempted_at", nextAttemptAt = "next_attempt_at"
        case errorReason = "error_reason", status, createdAt = "created_at", updatedAt = "updated_at"
    }
}

struct SyncQueueSummary: Equatable {
    let pendingCount: Int
    let inFlightCount: Int
    let failedCount: Int
    let poisonCount: Int
    let lastAttemptedAt: Date?
    let latestError: String?
}
