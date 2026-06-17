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

    // AMA-286: Weight capture support
    public let setNumber: Int?          // Current set number (1-based)
    public let totalSets: Int?          // Total sets for this exercise
    public let suggestedWeight: Double? // Pre-fill from last logged weight
    public let weightUnit: String?      // "lbs" or "kg"

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
        lastCommandAck: CommandAck?,
        setNumber: Int? = nil,
        totalSets: Int? = nil,
        suggestedWeight: Double? = nil,
        weightUnit: String? = nil
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
        self.setNumber = setNumber
        self.totalSets = totalSets
        self.suggestedWeight = suggestedWeight
        self.weightUnit = weightUnit
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

// MARK: - Standalone Workout Summary (Watch → Phone)

/// Summary sent from Watch to Phone after a standalone workout (no phone control).
/// Defined here once; compiled into both the AmakaFlowCompanion and AmakaFlowWatch targets.
public struct StandaloneWorkoutSummary: Codable {
    public let workoutId: String
    public let workoutName: String
    public let startDate: Date
    public let endDate: Date
    public let durationSeconds: Int
    public let totalCalories: Double
    public let averageHeartRate: Double?
    public let completedSteps: Int
    public let totalSteps: Int

    public init(
        workoutId: String,
        workoutName: String,
        startDate: Date,
        endDate: Date,
        durationSeconds: Int,
        totalCalories: Double,
        averageHeartRate: Double?,
        completedSteps: Int,
        totalSteps: Int
    ) {
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.totalCalories = totalCalories
        self.averageHeartRate = averageHeartRate
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
    }
}
