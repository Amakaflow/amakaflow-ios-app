//
//  PlanningModels.swift
//  AmakaFlow
//
//  Models for planning/day-state, conflict detection, and week generation APIs (AMA-1147)
//

import Foundation

// MARK: - Day State

/// Represents the training state for a single day
struct DayState: Codable, Identifiable {
    let date: String
    let readiness: ReadinessLevel
    let plannedWorkouts: [PlannedWorkout]
    let completedWorkouts: [String]
    let fatigueScore: Double?
    let notes: String?

    var id: String { date }
}

enum ReadinessLevel: String, Codable {
    case green
    case yellow
    case red
    case rest
    case unknown
}

struct PlannedWorkout: Codable, Identifiable {
    let id: String
    let name: String
    let sport: String
    let estimatedDurationMinutes: Int?
    let scheduledTime: String?
    let priority: WorkoutPriority?
}

enum WorkoutPriority: String, Codable {
    case key
    case normal
    case optional
}

// MARK: - Week Plan Generation

struct GenerateWeekRequest: Codable {
    let startDate: String?
    let preferences: WeekPreferences?
}

struct WeekPreferences: Codable {
    let maxDaysPerWeek: Int?
    let preferredRestDays: [Int]?
    let longRunDay: Int?
}

struct ProposedPlan: Codable {
    let weekStartDate: String
    let days: [ProposedDay]
    let rationale: String?
    let totalLoadScore: Double?
}

struct ProposedDay: Codable, Identifiable {
    let date: String
    let workouts: [PlannedWorkout]
    let isRestDay: Bool
    let rationale: String?

    var id: String { date }
}

// MARK: - Conflict Detection

struct DetectConflictsRequest: Codable {
    let startDate: String
    let endDate: String
}

struct Conflict: Codable, Identifiable {
    let id: String
    let date: String
    let type: ConflictType
    let description: String
    let severity: ConflictSeverity
    let suggestion: String?
}

enum ConflictType: String, Codable {
    case overload
    case backToBack = "back_to_back"
    case missingRecovery = "missing_recovery"
    case intensityClash = "intensity_clash"
}

enum ConflictSeverity: String, Codable {
    case low
    case medium
    case high
}

// MARK: - Parse Workout

struct ParseWorkoutRequest: Codable {
    let text: String
    let context: String?
}

struct ParsedWorkout: Codable {
    let name: String
    let sport: String
    let intervals: [WorkoutInterval]
    let estimatedDurationMinutes: Int?
    let confidence: Double?
}
