//
//  ProgramGenerationModels.swift
//  AmakaFlow
//
//  Models for program generation API (AMA-1413 / AMA-2096)
//

import Foundation

// MARK: - Retired async-job models

struct ProgramGenerationRequest: Codable {
    let goal: String
    let experienceLevel: String
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let preferredDays: [Int]
    let timePerSession: Int
    let equipment: [String]
    let injuries: String?
    let focusAreas: [String]?
    let avoidExercises: [String]?
}

struct ProgramGenerationResponse: Codable {
    let jobId: String
    let status: String
    let programId: String?
    let error: String?
}

struct ProgramGenerationStatus: Codable {
    let jobId: String
    let status: String
    let progress: Int
    let programId: String?
    let error: String?
}

// MARK: - Program Wizard SSE request models

struct DesignProgramRequest: Codable, Equatable {
    let goal: String
    let experienceLevel: String
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let equipment: [String]
    let timePerSession: Int?
    let preferredDays: [String]?
    let injuries: String?
    let focusAreas: [String]?
    let avoidExercises: [String]?
}

struct GenerateProgramPreviewRequest: Codable, Equatable {
    let previewId: String
}

struct SaveProgramPreviewRequest: Codable, Equatable {
    let previewId: String
    let scheduleStartDate: String?
}

// MARK: - Program Wizard SSE events

enum ProgramStreamEvent: Equatable {
    case stage(stage: String, message: String, subProgress: ProgramSubProgress?)
    case preview(previewId: String, payload: ProgramPreviewPayload)
    case complete(workoutIds: [String], scheduledCount: Int, workoutCount: Int?)
    case error(message: String, recoverable: Bool)
}

struct ProgramSubProgress: Codable, Equatable {
    let current: Int
    let total: Int
}

struct ProgramStagePayload: Codable, Equatable {
    let stage: String
    let message: String
    let subProgress: ProgramSubProgress?

    enum CodingKeys: String, CodingKey {
        case stage, message
        case subProgress = "sub_progress"
    }
}

struct ProgramPreviewPayload: Codable, Equatable {
    let previewId: String
    let program: ProposedProgram?
    let unmatched: [ProgramUnmatchedExercise]?

    enum CodingKeys: String, CodingKey {
        case previewId = "preview_id"
        case program, unmatched
    }
}

struct ProgramCompletePayload: Codable, Equatable {
    let programName: String?
    let workoutCount: Int?
    let workoutIds: [String]
    let scheduledCount: Int

    enum CodingKeys: String, CodingKey {
        case programName = "program_name"
        case workoutCount = "workout_count"
        case workoutIds = "workout_ids"
        case scheduledCount = "scheduled_count"
    }
}

struct ProgramErrorPayload: Codable, Equatable {
    let stage: String?
    let message: String
    let recoverable: Bool?
}

struct ProgramUnmatchedExercise: Codable, Identifiable, Equatable {
    let name: String
    let suggestions: [String]?

    var id: String { name }
}

// MARK: - Proposed program review model

struct ProposedProgram: Codable, Equatable {
    let id: String?
    let name: String
    let goal: String?
    let durationWeeks: Int?
    let sessionsPerWeek: Int?
    let periodizationModel: String?
    let weeks: [ProposedProgramWeek]

    enum CodingKeys: String, CodingKey {
        case id, name, goal, weeks
        case durationWeeks = "duration_weeks"
        case sessionsPerWeek = "sessions_per_week"
        case periodizationModel = "periodization_model"
    }

    var goalDisplayName: String? {
        guard let goal else { return nil }
        switch goal {
        case "strength": return "Strength"
        case "hypertrophy": return "Hypertrophy"
        case "fat_loss": return "Fat Loss"
        case "endurance": return "Endurance"
        case "general_fitness": return "General Fitness"
        default: return goal.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct ProposedProgramWeek: Codable, Identifiable, Equatable {
    let weekNumber: Int
    let focus: String?
    let intensityPercentage: Int?
    let volumeModifier: Double?
    let isDeload: Bool?
    let workouts: [ProposedProgramWorkout]

    enum CodingKeys: String, CodingKey {
        case focus, workouts
        case weekNumber = "week_number"
        case intensityPercentage = "intensity_percentage"
        case volumeModifier = "volume_modifier"
        case isDeload = "is_deload"
    }

    var id: Int { weekNumber }
}

struct ProposedProgramWorkout: Codable, Identifiable, Equatable {
    let name: String
    let dayOfWeek: Int?
    let workoutType: String?
    let targetDurationMinutes: Int?
    let exercises: [ProposedProgramExercise]

    enum CodingKeys: String, CodingKey {
        case name, exercises
        case dayOfWeek = "day_of_week"
        case workoutType = "workout_type"
        case targetDurationMinutes = "target_duration_minutes"
    }

    var id: String { "\(dayOfWeek ?? -1)-\(name)" }

    var dayName: String? {
        guard let dayOfWeek else { return nil }
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard dayOfWeek >= 0, dayOfWeek < days.count else { return "Day \(dayOfWeek)" }
        return days[dayOfWeek]
    }
}

struct ProposedProgramExercise: Codable, Identifiable, Equatable {
    let name: String
    let sets: Int?
    let reps: String?
    let restSeconds: Int?
    let notes: String?
    let tempo: String?
    let rpe: Int?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, notes, tempo, rpe
        case restSeconds = "rest_seconds"
    }

    var id: String { "\(name)-\(sets ?? 0)-\(reps ?? "")" }

    var setsRepsDisplay: String? {
        guard let sets, let reps else { return nil }
        return "\(sets) x \(reps)"
    }
}
