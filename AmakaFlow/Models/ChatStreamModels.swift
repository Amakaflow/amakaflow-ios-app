//
//  ChatStreamModels.swift
//  AmakaFlow
//
//  SSE streaming models for AI Coach chat (AMA-1410)
//

import Foundation

// MARK: - SSE Events

enum SSEEvent: Equatable {
    case messageStart(sessionId: String, traceId: String?)
    case contentDelta(text: String)
    case functionCall(id: String, name: String)
    case functionResult(toolUseId: String, name: String, result: String)
    case stage(stage: ChatStage, message: String)
    case heartbeat(status: String, toolName: String?, elapsedSeconds: Double?)
    case messageEnd(sessionId: String, tokensUsed: Int?, latencyMs: Int?)
    case error(type: String, message: String, usage: Int?, limit: Int?)
}

// MARK: - Chat Stage

enum ChatStage: String, Codable, CaseIterable {
    case analyzing
    case researching
    case searching
    case creating
    case complete

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .analyzing: return "sparkles"
        case .researching: return "person.fill"
        case .searching: return "magnifyingglass"
        case .creating: return "dumbbell.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Tool Call

struct ChatToolCall: Identifiable, Equatable {
    let id: String
    let name: String
    var status: Status
    var result: String?
    var elapsedSeconds: Double?

    enum Status: Equatable {
        case pending, running, completed, error
    }

    var displayName: String {
        switch name {
        case "search_workout_library": return "Searching workouts"
        case "create_workout_plan": return "Creating workout plan"
        case "get_workout_history": return "Looking up history"
        case "get_calendar_events": return "Checking calendar"
        default: return "Working"
        }
    }

    var iconName: String {
        switch name {
        case "search_workout_library": return "magnifyingglass"
        case "create_workout_plan": return "dumbbell.fill"
        case "get_workout_history": return "clock.arrow.circlepath"
        case "get_calendar_events": return "calendar"
        default: return "wrench.fill"
        }
    }
}

// MARK: - Generated Workout (from tool results)

struct GeneratedWorkout: Codable, Equatable {
    let name: String?
    let duration: String?
    let difficulty: String?
    let exercises: [WorkoutExercise]
}

struct WorkoutExercise: Codable, Identifiable, Equatable {
    var id: String { name + (reps ?? "") + "\(sets ?? 0)" }
    let name: String
    let sets: Int?
    let reps: String?
    let muscleGroup: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, notes
        case muscleGroup = "muscle_group"
    }
}

// MARK: - Workout Search Result

struct WorkoutSearchResult: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let duration: String?
    let exerciseCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, duration
        case exerciseCount = "exercise_count"
    }
}

// MARK: - Stream Request

struct ChatStreamRequest: Codable {
    let message: String
    let sessionId: String?
    let context: ChatStreamContext?

    enum CodingKeys: String, CodingKey {
        case message
        case sessionId = "session_id"
        case context
    }
}

struct ChatStreamContext: Codable {
    let currentPage: String?
    let selectedWorkoutId: String?
    let selectedDate: String?

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case selectedWorkoutId = "selected_workout_id"
        case selectedDate = "selected_date"
    }
}

// MARK: - Rate Limit Info

struct RateLimitInfo: Equatable {
    let usage: Int
    let limit: Int
}
