//
//  WorkoutConnectivityModels.swift
//  AmakaFlowWatch Watch App
//
//  Shared models for WatchConnectivity between iPhone and Watch
//

import Foundation

// MARK: - Workout State (Phone → Watch)

/// State broadcast from iPhone to Watch to show workout progress
public struct WorkoutState: Codable {
    public let stateVersion: Int
    public let workoutId: String
    public let workoutName: String
    public let phase: WorkoutPhase
    public let stepIndex: Int
    public let stepCount: Int
    public let stepName: String
    public let stepType: StepType
    public let remainingMs: Int?
    public let roundInfo: String?
    public let targetReps: Int?
    public let lastCommandAck: CommandAck?

    public init(
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
        targetReps: Int? = nil,
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
        self.targetReps = targetReps
        self.lastCommandAck = lastCommandAck
    }
}

// MARK: - Workout Phase

public enum WorkoutPhase: String, Codable {
    case idle
    case running
    case paused
    case resting    // Rest period between steps (manual or timed)
    case ended
}

// MARK: - Step Type

public enum StepType: String, Codable {
    case timed
    case reps
    case distance
    case rest       // Rest interval (timed or manual)
}

// MARK: - Remote Command (Watch → Phone)

public enum RemoteCommand: String, Codable {
    case pause = "PAUSE"
    case resume = "RESUME"
    case nextStep = "NEXT_STEP"
    case previousStep = "PREV_STEP"
    case skipRest = "SKIP_REST"
    case end = "END"
}

// MARK: - Command Acknowledgment (Phone → Watch)

public struct CommandAck: Codable {
    public let commandId: String
    public let status: CommandStatus
    public let errorCode: String?

    public init(commandId: String, status: CommandStatus, errorCode: String? = nil) {
        self.commandId = commandId
        self.status = status
        self.errorCode = errorCode
    }
}

public enum CommandStatus: String, Codable {
    case success
    case error
}
