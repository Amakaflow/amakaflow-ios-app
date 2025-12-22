//
//  WatchWorkoutState.swift
//  AmakaFlowWatch Watch App
//
//  State models for receiving workout state from iPhone
//

import Foundation

// MARK: - Workout Phase

enum WatchWorkoutPhase: String, Codable {
    case idle
    case running
    case paused
    case ended
}

// MARK: - Step Type

enum WatchStepType: String, Codable {
    case timed
    case reps
    case distance
}

// MARK: - Workout State (received from iPhone)

struct WatchWorkoutState: Codable {
    let stateVersion: Int
    let workoutId: String
    let workoutName: String
    let phase: WatchWorkoutPhase
    let stepIndex: Int
    let stepCount: Int
    let stepName: String
    let stepType: WatchStepType
    let remainingMs: Int?
    let roundInfo: String?

    var formattedTime: String {
        guard let ms = remainingMs else { return "--:--" }
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var progress: Double {
        guard stepCount > 0 else { return 0 }
        return Double(stepIndex + 1) / Double(stepCount)
    }

    var isTimedStep: Bool {
        stepType == .timed
    }

    var isPaused: Bool {
        phase == .paused
    }

    var isActive: Bool {
        phase == .running || phase == .paused
    }
}

// MARK: - Remote Command (sent to iPhone)

enum WatchRemoteCommand: String, Codable {
    case pause = "PAUSE"
    case resume = "RESUME"
    case nextStep = "NEXT_STEP"
    case previousStep = "PREV_STEP"
    case end = "END"
}

// MARK: - Command Status

enum WatchCommandStatus: String, Codable {
    case success
    case error
}
