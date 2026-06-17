//
//  WorkoutState.swift
//  AmakaFlow
//
//  Phone-only workout engine state: persistence and end reasons.
//  Wire-contract types (WorkoutState, WorkoutPhase, StepType, RemoteCommand,
//  CommandAck, CommandStatus, StandaloneWorkoutSummary) live in
//  WorkoutConnectivityModels.swift which is compiled into both targets.
//

import Foundation

// MARK: - End Reason
enum EndReason: String, Codable {
    case completed      // Workout finished all steps
    case userEnded      // User ended early but saved progress
    case discarded      // User ended and chose not to save
    case savedForLater  // User paused to resume later
    case error          // Workout ended due to an error
}

// MARK: - Saved Workout State (for Resume Later)
struct SavedWorkoutProgress: Codable {
    let workoutId: String
    let workoutName: String
    let currentStepIndex: Int
    let elapsedSeconds: Int
    let savedAt: Date

    private static let storageKey = DefaultsKey.savedWorkoutProgress.rawValue

    /// Save workout progress to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
            print("🏋️ Saved workout progress: step \(currentStepIndex), elapsed \(elapsedSeconds)s")
        }
    }

    /// Load saved workout progress from UserDefaults
    static func load() -> SavedWorkoutProgress? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let progress = try? JSONDecoder().decode(SavedWorkoutProgress.self, from: data) else {
            return nil
        }
        return progress
    }

    /// Clear saved workout progress
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("🏋️ Cleared saved workout progress")
    }
}

