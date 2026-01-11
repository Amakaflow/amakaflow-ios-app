//
//  SimulationSettings.swift
//  AmakaFlow
//
//  Settings for workout simulation mode.
//  Part of AMA-271: Workout Simulation Mode
//

import Foundation
import SwiftUI
import Combine

// MARK: - Simulation Settings

/// Observable settings for workout simulation mode
@MainActor
final class SimulationSettings: ObservableObject {
    static let shared = SimulationSettings()

    // MARK: - Stored Settings

    /// Whether simulation mode is enabled
    @AppStorage("simulationEnabled") var isEnabled: Bool = false

    /// Speed multiplier (1.0 = real-time, 10.0 = 10x speed)
    @AppStorage("simulationSpeed") var speed: Double = 10.0

    /// Behavior profile name
    @AppStorage("simulationProfile") var profileName: String = "casual"

    /// Whether to generate fake health data
    @AppStorage("simulationGenerateHealth") var generateHealthData: Bool = true

    /// Custom resting heart rate
    @AppStorage("simulationRestingHR") var restingHR: Int = 70

    /// Custom max heart rate
    @AppStorage("simulationMaxHR") var maxHR: Int = 175

    // AMA-308: Weight simulation settings
    /// Whether to automatically select weights for strength exercises
    @AppStorage("simulationSimulateWeight") var simulateWeight: Bool = true

    /// Weight profile for simulated weights (beginner, intermediate, advanced)
    @AppStorage("simulationWeightProfile") var weightProfileName: String = "intermediate"

    // MARK: - Computed Properties

    /// Get the behavior profile based on name
    var behaviorProfile: UserBehaviorProfile {
        UserBehaviorProfile.named(profileName)
    }

    /// Get custom HR profile with user settings
    var hrProfile: HRProfile {
        HRProfile(restingHR: restingHR, maxHR: maxHR, recoveryRate: 1.0)
    }

    /// AMA-308: Get the weight profile based on name
    var weightProfile: WeightProfile {
        WeightProfile.fromName(weightProfileName)
    }

    /// Available speed options
    static let speedOptions: [(label: String, value: Double)] = [
        ("Real-time (1x)", 1.0),
        ("Fast (10x)", 10.0),
        ("Very Fast (30x)", 30.0),
        ("Instant (60x)", 60.0)
    ]

    /// Available behavior profiles
    static let profileOptions: [(label: String, value: String)] = [
        ("Efficient", "efficient"),
        ("Casual", "casual"),
        ("Distracted", "distracted")
    ]

    /// AMA-308: Available weight profiles
    static let weightProfileOptions: [(label: String, value: String, description: String)] = [
        ("Beginner", "beginner", "~95-135 lbs"),
        ("Intermediate", "intermediate", "~185-275 lbs"),
        ("Advanced", "advanced", "~315-495 lbs")
    ]

    // MARK: - Factory Methods

    /// Create a clock for the current settings
    func createClock() -> WorkoutClock {
        if isEnabled {
            return AcceleratedClock(speedMultiplier: speed)
        } else {
            return RealClock()
        }
    }

    /// Create user input provider for current settings
    func createUserInput(clock: WorkoutClock) -> UserInputProvider {
        if isEnabled {
            return SimulatedUserInput(clock: clock, profile: behaviorProfile)
        } else {
            return RealUserInput()
        }
    }

    /// Create health provider for current settings
    func createHealthProvider() -> HealthDataProvider? {
        guard isEnabled && generateHealthData else { return nil }
        return SimulatedHealthProvider(profile: hrProfile)
    }

    /// AMA-308: Create weight provider for current settings
    func createWeightProvider() -> SimulatedWeightProvider? {
        guard isEnabled && simulateWeight else { return nil }
        return SimulatedWeightProvider(profile: weightProfile)
    }

    // MARK: - Private Init (singleton)

    private init() {}
}

// MARK: - Speed Formatting

extension SimulationSettings {
    /// Format speed for display
    var speedDisplayString: String {
        if speed == 1.0 {
            return "1x (Real-time)"
        } else {
            return "\(Int(speed))x"
        }
    }
}
