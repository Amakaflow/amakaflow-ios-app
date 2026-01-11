//
//  SimulatedWeightProvider.swift
//  AmakaFlow
//
//  Generates realistic simulated weights for strength exercises.
//  Part of AMA-308: Simulate Weight Selection
//

import Foundation

// MARK: - Weight Profile

/// Strength level profile for weight simulation
enum WeightProfile: String, CaseIterable {
    case beginner      // Lower weight ranges - new to lifting
    case intermediate  // Standard ranges - regular gym-goer
    case advanced      // Higher ranges - experienced lifter

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    /// Description showing approximate weight range (for barbell compound)
    var description: String {
        switch self {
        case .beginner: return "~95-135 lbs"
        case .intermediate: return "~185-275 lbs"
        case .advanced: return "~315-495 lbs"
        }
    }

    static func fromName(_ name: String) -> WeightProfile {
        switch name.lowercased() {
        case "beginner": return .beginner
        case "advanced": return .advanced
        default: return .intermediate
        }
    }
}

// MARK: - Exercise Type

/// Exercise type classification for weight selection
enum ExerciseType {
    case barbellCompound  // Squat, Deadlift - heavier
    case barbellUpper     // Bench Press, OHP - moderate
    case dumbbell         // Per-hand exercises
    case cable            // Cable machine exercises
    case machine          // Weight stack machines
    case kettlebell       // Kettlebell exercises
    case bodyweight       // No external weight needed
    case unknown          // Fallback
}

// MARK: - Weight Range

/// Weight range for an exercise type at a given profile level
/// Values are in lbs, will be converted if kg is selected
struct WeightRange {
    let min: Double
    let max: Double

    /// Get a random weight within this range, with ±10% variance
    func randomWeight() -> Double {
        let midpoint = (min + max) / 2
        let variance = midpoint * 0.1 * (Double.random(in: -1...1)) // ±10%
        let weight = midpoint + variance
        // Round to nearest 5 (standard weight increment)
        return (weight / 5).rounded() * 5
    }
}

// MARK: - Simulated Weight Provider

/// Generates realistic simulated weights for strength exercises
/// Uses exercise name classification and user's strength profile
class SimulatedWeightProvider {
    private let profile: WeightProfile

    private static let lbsToKg = 0.453592

    /// Weight ranges by exercise type and profile (in lbs)
    private static let weightRanges: [ExerciseType: [WeightProfile: WeightRange]] = [
        .barbellCompound: [
            .beginner: WeightRange(min: 95, max: 135),
            .intermediate: WeightRange(min: 185, max: 275),
            .advanced: WeightRange(min: 315, max: 495)
        ],
        .barbellUpper: [
            .beginner: WeightRange(min: 65, max: 95),
            .intermediate: WeightRange(min: 135, max: 185),
            .advanced: WeightRange(min: 225, max: 315)
        ],
        .dumbbell: [
            .beginner: WeightRange(min: 15, max: 25),
            .intermediate: WeightRange(min: 35, max: 50),
            .advanced: WeightRange(min: 60, max: 100)
        ],
        .cable: [
            .beginner: WeightRange(min: 30, max: 50),
            .intermediate: WeightRange(min: 60, max: 90),
            .advanced: WeightRange(min: 100, max: 150)
        ],
        .machine: [
            .beginner: WeightRange(min: 50, max: 80),
            .intermediate: WeightRange(min: 100, max: 150),
            .advanced: WeightRange(min: 180, max: 250)
        ],
        .kettlebell: [
            .beginner: WeightRange(min: 25, max: 35),
            .intermediate: WeightRange(min: 45, max: 60),
            .advanced: WeightRange(min: 70, max: 100)
        ]
    ]

    /// Default weight range for unknown exercises
    private static let defaultRanges: [WeightProfile: WeightRange] = [
        .beginner: WeightRange(min: 30, max: 50),
        .intermediate: WeightRange(min: 60, max: 90),
        .advanced: WeightRange(min: 100, max: 140)
    ]

    init(profile: WeightProfile) {
        self.profile = profile
    }

    /// Get a simulated weight for an exercise
    /// - Parameters:
    ///   - exerciseName: The name of the exercise (e.g., "Bench Press", "Squat")
    ///   - unit: Weight unit ("lbs" or "kg")
    /// - Returns: Simulated weight with realistic variance, or nil for bodyweight exercises
    func getSimulatedWeight(exerciseName: String, unit: String) -> Double? {
        let exerciseType = classifyExercise(exerciseName)

        // Bodyweight exercises don't need weight
        if exerciseType == .bodyweight {
            return nil
        }

        let range = Self.weightRanges[exerciseType]?[profile]
            ?? Self.defaultRanges[profile]
            ?? WeightRange(min: 50, max: 80)

        let weightLbs = range.randomWeight()

        if unit.lowercased() == "kg" {
            // Convert to kg and round to nearest 2.5 (standard kg plate increment)
            let weightKg = weightLbs * Self.lbsToKg
            return (weightKg / 2.5).rounded() * 2.5
        } else {
            return weightLbs
        }
    }

    /// Classify an exercise by name to determine appropriate weight range
    func classifyExercise(_ name: String) -> ExerciseType {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)

        // Barbell compound movements (heavy lower body and full-body lifts)
        if (normalized.contains("squat") && !normalized.contains("goblet")) ||
           normalized.contains("deadlift") ||
           normalized.contains("clean") ||
           normalized.contains("snatch") {
            return .barbellCompound
        }

        // Barbell upper body movements
        if normalized.contains("barbell") ||
           normalized.contains("bench press") ||
           normalized.contains("overhead press") ||
           normalized.contains("ohp") ||
           normalized.contains("military press") ||
           (normalized.contains("row") && !normalized.contains("dumbbell") && !normalized.contains("cable")) {
            return .barbellUpper
        }

        // Dumbbell exercises
        if normalized.contains("dumbbell") ||
           normalized.contains("db ") ||
           normalized.hasPrefix("db") ||
           (normalized.contains("curl") && !normalized.contains("cable")) ||
           normalized.contains("lateral raise") ||
           (normalized.contains("fly") && !normalized.contains("cable")) ||
           normalized.contains("kickback") ||
           normalized.contains("hammer") ||
           normalized.contains("concentration") {
            return .dumbbell
        }

        // Cable exercises
        if normalized.contains("cable") ||
           normalized.contains("pulldown") ||
           normalized.contains("tricep pushdown") ||
           normalized.contains("face pull") ||
           normalized.contains("crossover") {
            return .cable
        }

        // Machine exercises
        if normalized.contains("machine") ||
           normalized.contains("leg press") ||
           (normalized.contains("chest press") && !normalized.contains("dumbbell")) ||
           normalized.contains("leg curl") ||
           normalized.contains("leg extension") ||
           normalized.contains("seated row") ||
           normalized.contains("hack squat") ||
           normalized.contains("smith") {
            return .machine
        }

        // Kettlebell exercises
        if normalized.contains("kettlebell") ||
           normalized.contains("kb ") ||
           normalized.hasPrefix("kb") ||
           normalized.contains("swing") ||
           normalized.contains("goblet") ||
           normalized.contains("turkish get") {
            return .kettlebell
        }

        // Bodyweight exercises - no weight needed
        if normalized.contains("push-up") ||
           normalized.contains("pushup") ||
           normalized.contains("pull-up") ||
           normalized.contains("pullup") ||
           normalized.contains("chin-up") ||
           normalized.contains("chinup") ||
           (normalized.contains("dip") && !normalized.contains("weight")) ||
           normalized.contains("plank") ||
           normalized.contains("crunch") ||
           normalized.contains("sit-up") ||
           normalized.contains("situp") ||
           normalized.contains("burpee") ||
           normalized.contains("mountain climber") ||
           normalized.contains("jumping jack") ||
           normalized.contains("bodyweight") {
            return .bodyweight
        }

        return .unknown
    }
}
