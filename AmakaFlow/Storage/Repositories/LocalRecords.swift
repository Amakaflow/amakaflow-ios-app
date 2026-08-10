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
    /// AMA-1823: per-attempt UUID stamped before each sync attempt and
    /// echoed as the `X-Request-ID` header on the upstream call. Nullable
    /// because rows enqueued before the V2 migration (or freshly enqueued
    /// rows that have not yet been attempted) won't have one.
    var requestId: String?

    enum Columns: String, ColumnExpression {
        case id, resourceType = "resource_type", resourceId = "resource_id", op, payload
        case attemptCount = "attempt_count", lastAttemptedAt = "last_attempted_at", nextAttemptAt = "next_attempt_at"
        case errorReason = "error_reason", status, createdAt = "created_at", updatedAt = "updated_at"
        case requestId = "request_id"
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
        case requestId = "request_id"
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

struct LocalWorkoutCollection: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "workout_collections"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    var id: String
    var name: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, name, note, createdAt = "created_at", updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LocalWorkoutCollectionMember: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    static let databaseTableName = "workout_collection_members"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    var collectionId: String
    var workoutId: String
    var position: Int

    enum Columns: String, ColumnExpression {
        case collectionId = "collection_id", workoutId = "workout_id", position
    }

    enum CodingKeys: String, CodingKey {
        case collectionId = "collection_id"
        case workoutId = "workout_id"
        case position
    }
}

struct LocalPinnedWorkout: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "pinned_workouts"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    var workoutId: String
    var pinnedAt: Date

    var id: String { workoutId }

    enum Columns: String, ColumnExpression {
        case workoutId = "workout_id", pinnedAt = "pinned_at"
    }

    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case pinnedAt = "pinned_at"
    }
}

/// AMA-2387: verified fill-in session (local-first; sync later).
/// AMA-2396: extended with per-session Strava write-back state so un-verify /
/// remove-from-Strava can restore what was there before us without a re-fetch.
struct LocalActualsSession: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "actuals_sessions"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    var id: String
    var title: String
    var subtitle: String
    var rpe: Int?
    var verified: Bool
    var savedAt: Date
    var createdAt: Date
    /// `StravaDecorationState.persistedRawValue` — nil means no Strava involvement.
    var stravaDecoration: String?
    /// Snapshot of Strava's title/description before our first write (restore-on-unverify).
    var preUpdateTitle: String?
    var preUpdateDescription: String?
    /// Originating Strava activity id when this session came from a synced activity.
    var stravaActivityId: String?
    /// Un-verify keeps exercise rows but drops the session back to a draft — never
    /// deletes the fill-in the athlete already did.
    var isDraft: Bool
    /// AMA-2396 V6: write-back skip-rule inputs (must survive relaunch).
    var stravaActivityType: String?
    var stravaCurrentDescription: String?
    var stravaRecordingApp: String?
    var stravaIsRace: Bool
    /// AMA-2396 V7: full workout structure text for Strava write-back.
    var structureBody: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        rpe: Int? = nil,
        verified: Bool,
        savedAt: Date,
        createdAt: Date,
        stravaDecoration: String? = nil,
        preUpdateTitle: String? = nil,
        preUpdateDescription: String? = nil,
        stravaActivityId: String? = nil,
        isDraft: Bool = false,
        stravaActivityType: String? = nil,
        stravaCurrentDescription: String? = nil,
        stravaRecordingApp: String? = nil,
        stravaIsRace: Bool = false,
        structureBody: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.rpe = rpe
        self.verified = verified
        self.savedAt = savedAt
        self.createdAt = createdAt
        self.stravaDecoration = stravaDecoration
        self.preUpdateTitle = preUpdateTitle
        self.preUpdateDescription = preUpdateDescription
        self.stravaActivityId = stravaActivityId
        self.isDraft = isDraft
        self.stravaActivityType = stravaActivityType
        self.stravaCurrentDescription = stravaCurrentDescription
        self.stravaRecordingApp = stravaRecordingApp
        self.stravaIsRace = stravaIsRace
        self.structureBody = structureBody
    }

    enum Columns: String, ColumnExpression {
        case id, title, subtitle, rpe, verified
        case savedAt = "saved_at", createdAt = "created_at"
        case stravaDecoration = "strava_decoration"
        case preUpdateTitle = "pre_update_title"
        case preUpdateDescription = "pre_update_description"
        case stravaActivityId = "strava_activity_id"
        case isDraft = "is_draft"
        case stravaActivityType = "strava_activity_type"
        case stravaCurrentDescription = "strava_current_description"
        case stravaRecordingApp = "strava_recording_app"
        case stravaIsRace = "strava_is_race"
        case structureBody = "structure_body"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, rpe, verified
        case savedAt = "saved_at"
        case createdAt = "created_at"
        case stravaDecoration = "strava_decoration"
        case preUpdateTitle = "pre_update_title"
        case preUpdateDescription = "pre_update_description"
        case stravaActivityId = "strava_activity_id"
        case isDraft = "is_draft"
        case stravaActivityType = "strava_activity_type"
        case stravaCurrentDescription = "strava_current_description"
        case stravaRecordingApp = "strava_recording_app"
        case stravaIsRace = "strava_is_race"
        case structureBody = "structure_body"
    }
}

extension LocalActualsSession {
    /// Keep Strava write-back metadata when a verified session is re-saved.
    mutating func preserveWriteBack(
        from existing: LocalActualsSession,
        includeDraftFields: Bool = false
    ) {
        createdAt = existing.createdAt
        stravaDecoration = existing.stravaDecoration
        preUpdateTitle = existing.preUpdateTitle
        preUpdateDescription = existing.preUpdateDescription
        if includeDraftFields {
            isDraft = false
        }
        if stravaActivityId == nil {
            stravaActivityId = existing.stravaActivityId
        }
        if stravaActivityType == nil {
            stravaActivityType = existing.stravaActivityType
        }
        if stravaCurrentDescription == nil {
            stravaCurrentDescription = existing.stravaCurrentDescription
        }
        if stravaRecordingApp == nil {
            stravaRecordingApp = existing.stravaRecordingApp
        }
        if structureBody == nil {
            structureBody = existing.structureBody
        }
    }
}

struct LocalActualsExerciseRow: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "actuals_exercise_rows"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    var id: String
    var sessionId: String
    var exerciseKey: String
    var name: String
    var plannedSets: Int
    var plannedReps: Int
    var plannedWeightKg: Double?
    var plannedNote: String?
    var confirmation: String
    var actualSets: Int
    var actualReps: Int
    var actualWeightKg: Double?
    var position: Int
    var structureHeader: String?
    var structureBlockIndex: Int?

    enum Columns: String, ColumnExpression {
        case id, sessionId = "session_id", exerciseKey = "exercise_key", name
        case plannedSets = "planned_sets", plannedReps = "planned_reps"
        case plannedWeightKg = "planned_weight_kg", plannedNote = "planned_note"
        case confirmation
        case actualSets = "actual_sets", actualReps = "actual_reps"
        case actualWeightKg = "actual_weight_kg", position
        case structureHeader = "structure_header"
        case structureBlockIndex = "structure_block_index"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, confirmation, position
        case sessionId = "session_id"
        case exerciseKey = "exercise_key"
        case plannedSets = "planned_sets"
        case plannedReps = "planned_reps"
        case plannedWeightKg = "planned_weight_kg"
        case plannedNote = "planned_note"
        case actualSets = "actual_sets"
        case actualReps = "actual_reps"
        case actualWeightKg = "actual_weight_kg"
        case structureHeader = "structure_header"
        case structureBlockIndex = "structure_block_index"
    }
}
