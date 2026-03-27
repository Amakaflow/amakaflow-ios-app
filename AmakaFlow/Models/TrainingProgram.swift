//
//  TrainingProgram.swift
//  AmakaFlow
//
//  Data models for Training Programs (AMA-1231)
//

import Foundation

// MARK: - Training Program

struct TrainingProgram: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let goal: String
    let experienceLevel: String
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let status: String
    let equipmentAvailable: [String]?
    let weeks: [ProgramWeek]?
    let createdAt: String?
    let updatedAt: String?

    /// Human-readable goal label
    var goalDisplayName: String {
        switch goal {
        case "strength": return "Strength"
        case "hypertrophy": return "Hypertrophy"
        case "endurance": return "Endurance"
        case "weight_loss": return "Weight Loss"
        case "general_fitness": return "General Fitness"
        case "sport_specific": return "Sport Specific"
        default: return goal.capitalized
        }
    }

    /// Human-readable experience level label
    var experienceLevelDisplayName: String {
        experienceLevel.capitalized
    }

    /// Human-readable status label
    var statusDisplayName: String {
        status.capitalized
    }
}

// MARK: - Program Week

struct ProgramWeek: Codable, Identifiable {
    let id: String
    let weekNumber: Int
    let focus: String?
    let intensityPercentage: Int?
    let volumeModifier: Double
    let isDeload: Bool
    let workouts: [ProgramWorkout]?
}

// MARK: - Program Workout

struct ProgramWorkout: Codable, Identifiable {
    let id: String
    let dayOfWeek: Int
    let name: String
    let workoutType: String
    let targetDurationMinutes: Int?
    let exercises: [ProgramExercise]?
    let isCompleted: Bool?
    let completedAt: String?
    let notes: String?

    /// Day name from day_of_week (0=Monday, 6=Sunday)
    var dayName: String {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        guard dayOfWeek >= 0, dayOfWeek < days.count else { return "Day \(dayOfWeek)" }
        return days[dayOfWeek]
    }
}

// MARK: - Program Exercise

struct ProgramExercise: Codable, Identifiable {
    let name: String
    let sets: Int
    let reps: String
    let restSeconds: Int
    let weight: Double?
    let notes: String?
    let tempo: String?
    let rpe: Int?

    /// Synthesized id since exercises don't have UUIDs
    var id: String { "\(name)-\(sets)-\(reps)" }

    /// Formatted sets x reps display
    var setsRepsDisplay: String {
        "\(sets) x \(reps)"
    }

    /// Formatted rest display
    var restDisplay: String {
        if restSeconds >= 60 {
            let minutes = restSeconds / 60
            let seconds = restSeconds % 60
            return seconds > 0 ? "\(minutes)m \(seconds)s rest" : "\(minutes)m rest"
        }
        return "\(restSeconds)s rest"
    }
}

// MARK: - Programs List Response

struct ProgramsResponse: Codable {
    let programs: [TrainingProgram]
    let total: Int?
    let limit: Int?
    let offset: Int?
}
