//
//  WorkoutState.swift
//  AmakaFlow
//
//  State models for the workout engine
//

import Foundation

// MARK: - Workout Phase
enum WorkoutPhase: String, Codable {
    case idle
    case running
    case paused
    case ended
}

// MARK: - Step Type
enum StepType: String, Codable {
    case timed      // Has countdown timer
    case reps       // Manual completion
    case distance   // Distance-based
}

// MARK: - End Reason
enum EndReason: String, Codable {
    case completed
    case userEnded
    case error
}

// MARK: - Workout State (for broadcasting)
struct WorkoutState: Codable {
    let stateVersion: Int
    let workoutId: String
    let workoutName: String
    let phase: WorkoutPhase
    let stepIndex: Int
    let stepCount: Int
    let stepName: String
    let stepType: StepType
    let remainingMs: Int?
    let roundInfo: String?
    let lastCommandAck: CommandAck?

    init(
        stateVersion: Int,
        workoutId: String,
        workoutName: String,
        phase: WorkoutPhase,
        stepIndex: Int,
        stepCount: Int,
        stepName: String,
        stepType: StepType,
        remainingMs: Int?,
        roundInfo: String?,
        lastCommandAck: CommandAck?
    ) {
        self.stateVersion = stateVersion
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.phase = phase
        self.stepIndex = stepIndex
        self.stepCount = stepCount
        self.stepName = stepName
        self.stepType = stepType
        self.remainingMs = remainingMs
        self.roundInfo = roundInfo
        self.lastCommandAck = lastCommandAck
    }
}

// MARK: - Command Acknowledgment
struct CommandAck: Codable {
    let commandId: String
    let status: CommandStatus
    let errorCode: String?
}

enum CommandStatus: String, Codable {
    case success
    case error
}

// MARK: - Remote Command
enum RemoteCommand: String, Codable {
    case pause = "PAUSE"
    case resume = "RESUME"
    case nextStep = "NEXT_STEP"
    case previousStep = "PREV_STEP"
    case end = "END"
}
