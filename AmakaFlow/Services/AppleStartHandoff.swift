//
//  AppleStartHandoff.swift
//  AmakaFlow
//
//  AMA-2287: Library → Start → Apple try — WatchConnectivity + WorkoutKit fallback.
//

import Foundation
import WorkoutKitSync

/// Outcome of Start → Apple for in-app status copy (seconds, not minutes).
struct AppleStartHandoffResult: Equatable {
    enum Kind: Equatable {
        case sentToWatch
        case savedToFitness
        case failed
        case blocked
    }

    let kind: Kind
    /// User-facing status line shown under detail actions.
    let message: String
}

enum AppleStartHandoffFailureCode: String, Equatable {
    case watchNotReachable = "watch_not_reachable"
    case watchAppNotInstalled = "watch_app_not_installed"
    case sessionNotAvailable = "session_not_available"
    case encodingFailed = "encoding_failed"
    case watchSendFailed = "watch_send_failed"
    case watchDecodeFailed = "watch_decode_failed"
    case authorizationDenied = "authorization_denied"
    case conversionFailed = "conversion_failed"
    case iosVersionUnsupported = "ios_version_unsupported"
    case emptyWorkout = "empty_workout"
    case unknown = "unknown"
}

/// Pure mapping for unit tests — keep recoverable copy ≤ a few seconds to read.
enum AppleStartHandoffCopy {
    static func failureMessage(code: AppleStartHandoffFailureCode, detail: String? = nil) -> String {
        switch code {
        case .watchNotReachable:
            return "Apple Watch not reachable — unlock watch, open AmakaFlowWatch, keep iPhone nearby."
        case .watchAppNotInstalled:
            return "AmakaFlowWatch not installed — install the watch app from the Watch app on iPhone."
        case .sessionNotAvailable:
            return "Watch connectivity unavailable — restart both apps and try again."
        case .encodingFailed:
            return "Could not encode workout for Watch — edit structure and retry."
        case .watchSendFailed:
            if let detail, !detail.isEmpty {
                return "Watch send failed — \(detail)"
            }
            return "Watch send failed — confirm AmakaFlowWatch is open, then retry."
        case .watchDecodeFailed:
            return "Watch could not read workout — simplify intervals and retry."
        case .authorizationDenied:
            return "Apple Fitness permission denied — Settings → Health → Data Access → AmakaFlow, allow Workouts."
        case .conversionFailed:
            if let detail, !detail.isEmpty {
                return "WorkoutKit conversion failed — \(detail)"
            }
            return "WorkoutKit conversion failed — check intervals use supported step types."
        case .iosVersionUnsupported:
            return "Requires iOS 18 for Apple Fitness save — update iPhone or send while Watch is reachable."
        case .emptyWorkout:
            return "Workout has no steps — add exercises or intervals in Edit, then retry."
        case .unknown:
            if let detail, !detail.isEmpty {
                return "Apple try failed — \(detail)"
            }
            return "Apple try failed — check Watch pairing and retry."
        }
    }

    static func sentToWatchMessage(workoutName: String) -> AppleStartHandoffResult {
        AppleStartHandoffResult(
            kind: .sentToWatch,
            message: "Sent to Apple Watch — open AmakaFlowWatch to start \"\(workoutName)\"."
        )
    }

    static func savedToFitnessMessage(workoutName: String) -> AppleStartHandoffResult {
        AppleStartHandoffResult(
            kind: .savedToFitness,
            message: "Saved to Apple Fitness — open Workout app on iPhone or Watch for \"\(workoutName)\"."
        )
    }

    static func failureCode(from watchError: WatchConnectivityError) -> AppleStartHandoffFailureCode {
        switch watchError {
        case .watchNotReachable:
            return .watchNotReachable
        case .encodingFailed:
            return .encodingFailed
        case .sessionNotAvailable:
            return .sessionNotAvailable
        }
    }

    static func failureCode(from error: Error) -> AppleStartHandoffFailureCode {
        if let watchError = error as? WatchConnectivityError {
            return failureCode(from: watchError)
        }
        if let planError = error as? WorkoutPlanError {
            switch planError {
            case .authorizationDenied:
                return .authorizationDenied
            case .conversionFailed, .parsingFailed, .invalidJSONString:
                return .conversionFailed
            case .saveFailed:
                return .unknown
            }
        }
        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("authorization") || lowered.contains("denied") {
            return .authorizationDenied
        }
        return .unknown
    }
}

/// Outcome of a single WatchConnectivity send attempt.
enum WatchWorkoutSendOutcome: Equatable {
    case sent
    case failed(WatchConnectivityError)
    case watchRejected(String)
}

/// Test seam for WorkoutKit saves without linking WorkoutKit in unit tests.
protocol WorkoutKitSaving: Sendable {
    func saveToWorkoutKit(_ workout: Workout) async throws
}

@available(iOS 18.0, *)
struct LiveWorkoutKitSaver: WorkoutKitSaving {
    func saveToWorkoutKit(_ workout: Workout) async throws {
        try await WorkoutKitConverter.shared.saveToWorkoutKit(workout)
    }
}

/// Coordinates Watch send + WorkoutKit fallback for Start → Apple try.
@MainActor
final class AppleStartHandoffService {
    private let watchManager: WatchConnectivityManager
    private let workoutKitSaver: (any WorkoutKitSaving)?
    private let forceFailureCode: (() -> AppleStartHandoffFailureCode?)?

    init(
        watchManager: WatchConnectivityManager = .shared,
        workoutKitSaver: (any WorkoutKitSaving)? = nil,
        forceFailureCode: (() -> AppleStartHandoffFailureCode?)? = nil
    ) {
        self.watchManager = watchManager
        if #available(iOS 18.0, *) {
            self.workoutKitSaver = workoutKitSaver ?? LiveWorkoutKitSaver()
        } else {
            self.workoutKitSaver = nil
        }
        self.forceFailureCode = forceFailureCode ?? {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["UITEST_APPLE_TRY_FAIL"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                return AppleStartHandoffFailureCode(rawValue: raw) ?? .unknown
            }
            #endif
            return nil
        }
    }

    func handoff(workout: Workout, watchReachable: Bool) async -> AppleStartHandoffResult {
        if let forced = forceFailureCode?() {
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(code: forced)
            )
        }

        if workout.intervals.isEmpty {
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(code: .emptyWorkout)
            )
        }

        if watchReachable {
            let sendOutcome = await watchManager.sendWorkoutWithOutcome(workout)
            switch sendOutcome {
            case .sent:
                return AppleStartHandoffCopy.sentToWatchMessage(workoutName: workout.name)
            case .watchRejected(let reason):
                if let fitness = await saveToFitnessFallback(workout: workout, priorFailure: .watchDecodeFailed, detail: reason) {
                    return fitness
                }
                return AppleStartHandoffResult(
                    kind: .failed,
                    message: AppleStartHandoffCopy.failureMessage(code: .watchDecodeFailed, detail: reason)
                )
            case .failed(let error):
                if let fitness = await saveToFitnessFallback(workout: workout, priorFailure: AppleStartHandoffCopy.failureCode(from: error), detail: error.localizedDescription) {
                    return fitness
                }
                return AppleStartHandoffResult(
                    kind: .failed,
                    message: AppleStartHandoffCopy.failureMessage(
                        code: AppleStartHandoffCopy.failureCode(from: error),
                        detail: error.localizedDescription
                    )
                )
            }
        }

        if let fitness = await saveToFitnessFallback(workout: workout, priorFailure: .watchNotReachable, detail: nil) {
            return fitness
        }

        if #available(iOS 18.0, *) {
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(code: .watchNotReachable)
            )
        }

        return AppleStartHandoffResult(
            kind: .blocked,
            message: AppleStartHandoffCopy.failureMessage(code: .iosVersionUnsupported)
        )
    }

    private func saveToFitnessFallback(
        workout: Workout,
        priorFailure: AppleStartHandoffFailureCode,
        detail: String?
    ) async -> AppleStartHandoffResult? {
        guard #available(iOS 18.0, *), let workoutKitSaver else { return nil }
        do {
            try await workoutKitSaver.saveToWorkoutKit(workout)
            return AppleStartHandoffCopy.savedToFitnessMessage(workoutName: workout.name)
        } catch {
            let code = AppleStartHandoffCopy.failureCode(from: error)
            // Surface the primary blocker when fallback also fails.
            let primary = priorFailure == .watchNotReachable ? priorFailure : code
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(
                    code: primary,
                    detail: detail ?? error.localizedDescription
                )
            )
        }
    }
}
