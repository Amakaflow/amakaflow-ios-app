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

func encodeToJSONString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
}

struct LocalAcceptedSuggestion: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "accepted_suggestions"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

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

    enum CodingKeys: String, CodingKey {
        case id, status
        case userId = "user_id"
        case suggestionId = "suggestion_id"
        case workoutEventId = "workout_event_id"
        case clientGeneratedId = "client_generated_id"
        case serverVersion = "server_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct LocalWorkoutEvent: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "workout_events"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

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

    enum CodingKeys: String, CodingKey {
        case id, date, status, source
        case userId = "user_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case jsonPayload = "json_payload"
        case clientGeneratedId = "client_generated_id"
        case serverVersion = "server_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct LocalAIRun: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "ai_runs"

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

    enum CodingKeys: String, CodingKey {
        case id, kind, model, input, output
        case userId = "user_id"
        case promptVersion = "prompt_version"
        case latencyMs = "latency_ms"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUsd = "cost_usd"
        case createdAt = "created_at"
    }
}

struct SyncQueueItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "sync_queue"

    var id: String
    var resourceType: String
    var resourceId: String
    var op: String
    var payload: String
    var attemptCount: Int
    var lastAttemptedAt: Date?
    var nextAttemptAt: Date?
    var errorReason: String?
    var status: SyncQueueStatus
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, resourceType = "resource_type", resourceId = "resource_id", op, payload
        case attemptCount = "attempt_count", lastAttemptedAt = "last_attempted_at", nextAttemptAt = "next_attempt_at"
        case errorReason = "error_reason", status, createdAt = "created_at", updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id, op, payload, status
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case attemptCount = "attempt_count"
        case lastAttemptedAt = "last_attempted_at"
        case nextAttemptAt = "next_attempt_at"
        case errorReason = "error_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
