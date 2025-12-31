//
//  WatchWorkoutState.swift
//  AmakaFlowWatch Watch App
//
//  State models for receiving workout state from iPhone
//  Uses shared WorkoutConnectivityModels for compatibility
//

import Foundation

// MARK: - Type Aliases for Watch-side naming

typealias WatchWorkoutState = WorkoutState
typealias WatchWorkoutPhase = WorkoutPhase
typealias WatchStepType = StepType
typealias WatchRemoteCommand = RemoteCommand
typealias WatchCommandStatus = CommandStatus

// MARK: - Watch-specific Extensions

extension WorkoutState {
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
        phase == .running || phase == .paused || phase == .resting
    }

    var isResting: Bool {
        phase == .resting
    }
}
