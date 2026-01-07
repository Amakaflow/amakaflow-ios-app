//
//  UserBehaviorProfile.swift
//  AmakaFlow
//
//  Configurable user behavior profiles for workout simulation.
//  Part of AMA-271: Workout Simulation Mode
//

import Foundation

// MARK: - User Behavior Profile

/// Defines simulated user behavior patterns during workouts
struct UserBehaviorProfile: Codable, Equatable {
    /// Multiplier range for rest time (e.g., 0.9-1.0 means taking 90-100% of prescribed rest)
    let restTimeMultiplier: ClosedRange<Double>

    /// Probability of pausing mid-workout (0.0 - 1.0)
    let pauseProbability: Double

    /// Duration range for pauses in seconds
    let pauseDuration: ClosedRange<TimeInterval>

    /// Reaction time range in seconds (delay before tapping "next" or "done")
    let reactionTime: ClosedRange<TimeInterval>

    /// Probability of skipping a step (0.0 - 1.0)
    let skipProbability: Double

    /// Heart rate simulation profile
    let hrProfile: HRProfile

    // MARK: - Codable Support for ClosedRange

    enum CodingKeys: String, CodingKey {
        case restTimeMultiplierMin, restTimeMultiplierMax
        case pauseProbability
        case pauseDurationMin, pauseDurationMax
        case reactionTimeMin, reactionTimeMax
        case skipProbability
        case hrProfile
    }

    init(
        restTimeMultiplier: ClosedRange<Double>,
        pauseProbability: Double,
        pauseDuration: ClosedRange<TimeInterval>,
        reactionTime: ClosedRange<TimeInterval>,
        skipProbability: Double,
        hrProfile: HRProfile
    ) {
        self.restTimeMultiplier = restTimeMultiplier
        self.pauseProbability = pauseProbability
        self.pauseDuration = pauseDuration
        self.reactionTime = reactionTime
        self.skipProbability = skipProbability
        self.hrProfile = hrProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let restMin = try container.decode(Double.self, forKey: .restTimeMultiplierMin)
        let restMax = try container.decode(Double.self, forKey: .restTimeMultiplierMax)
        restTimeMultiplier = restMin...restMax

        pauseProbability = try container.decode(Double.self, forKey: .pauseProbability)

        let pauseMin = try container.decode(TimeInterval.self, forKey: .pauseDurationMin)
        let pauseMax = try container.decode(TimeInterval.self, forKey: .pauseDurationMax)
        pauseDuration = pauseMin...pauseMax

        let reactionMin = try container.decode(TimeInterval.self, forKey: .reactionTimeMin)
        let reactionMax = try container.decode(TimeInterval.self, forKey: .reactionTimeMax)
        reactionTime = reactionMin...reactionMax

        skipProbability = try container.decode(Double.self, forKey: .skipProbability)
        hrProfile = try container.decode(HRProfile.self, forKey: .hrProfile)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(restTimeMultiplier.lowerBound, forKey: .restTimeMultiplierMin)
        try container.encode(restTimeMultiplier.upperBound, forKey: .restTimeMultiplierMax)
        try container.encode(pauseProbability, forKey: .pauseProbability)
        try container.encode(pauseDuration.lowerBound, forKey: .pauseDurationMin)
        try container.encode(pauseDuration.upperBound, forKey: .pauseDurationMax)
        try container.encode(reactionTime.lowerBound, forKey: .reactionTimeMin)
        try container.encode(reactionTime.upperBound, forKey: .reactionTimeMax)
        try container.encode(skipProbability, forKey: .skipProbability)
        try container.encode(hrProfile, forKey: .hrProfile)
    }

    // MARK: - Preset Profiles

    /// Efficient user - takes minimal rest, fast reactions, rarely pauses
    static let efficient = UserBehaviorProfile(
        restTimeMultiplier: 0.9...1.0,
        pauseProbability: 0.05,
        pauseDuration: 5...15,
        reactionTime: 0.3...1.0,
        skipProbability: 0.02,
        hrProfile: .athletic
    )

    /// Casual user - normal rest times, occasional pauses
    static let casual = UserBehaviorProfile(
        restTimeMultiplier: 1.0...1.5,
        pauseProbability: 0.15,
        pauseDuration: 15...90,
        reactionTime: 1.0...3.0,
        skipProbability: 0.1,
        hrProfile: .average
    )

    /// Distracted user - extended rest, frequent pauses, sometimes skips
    static let distracted = UserBehaviorProfile(
        restTimeMultiplier: 1.2...2.5,
        pauseProbability: 0.3,
        pauseDuration: 30...180,
        reactionTime: 2.0...8.0,
        skipProbability: 0.15,
        hrProfile: .average
    )

    /// Get profile by name
    static func named(_ name: String) -> UserBehaviorProfile {
        switch name {
        case "efficient": return .efficient
        case "distracted": return .distracted
        default: return .casual
        }
    }
}

// MARK: - HR Profile

/// Heart rate simulation parameters
struct HRProfile: Codable, Equatable {
    /// Resting heart rate in BPM
    let restingHR: Int

    /// Maximum heart rate in BPM
    let maxHR: Int

    /// Recovery rate - BPM drop per minute of rest
    let recoveryRate: Double

    // MARK: - Presets

    /// Athletic user - lower resting HR, higher max HR, faster recovery
    static let athletic = HRProfile(
        restingHR: 55,
        maxHR: 185,
        recoveryRate: 1.5
    )

    /// Average user
    static let average = HRProfile(
        restingHR: 70,
        maxHR: 175,
        recoveryRate: 1.0
    )

    /// Beginner user - higher resting HR, lower max HR, slower recovery
    static let beginner = HRProfile(
        restingHR: 80,
        maxHR: 165,
        recoveryRate: 0.7
    )

    // MARK: - HR Zone Calculation

    /// Calculate heart rate for a given intensity level
    func hrForIntensity(_ intensity: ExerciseIntensity) -> Int {
        let hrReserve = maxHR - restingHR
        let targetPercent: Double

        switch intensity {
        case .rest:
            targetPercent = 0.1
        case .low:
            targetPercent = 0.5
        case .moderate:
            targetPercent = 0.7
        case .high:
            targetPercent = 0.85
        case .max:
            targetPercent = 0.95
        }

        return restingHR + Int(Double(hrReserve) * targetPercent)
    }
}

// MARK: - Exercise Intensity

/// Exercise intensity levels for HR simulation
enum ExerciseIntensity: String, Codable {
    case rest       // Recovery/rest periods
    case low        // Warm-up, cooldown
    case moderate   // Steady-state cardio
    case high       // High-intensity intervals
    case max        // Maximum effort bursts
}
