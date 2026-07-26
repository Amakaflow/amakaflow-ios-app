//
//  AppleStartHandoff.swift
//  AmakaFlow
//
//  AMA-2287: WorkoutKit-primary Start → Workout on Apple Watch.
//

import Foundation
import WatchConnectivity
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

enum AppleWatchPairingRead: Equatable {
    case confirmedPaired
    case confirmedUnpaired
    case unknown

    /// Optimistic: unknown / not activated → paired-style copy. Unpaired only when activated and not paired.
    static func resolve(from session: (any WatchSessionProviding)?) -> AppleWatchPairingRead {
        guard let session else { return .unknown }
        guard session.activationState == .activated else { return .unknown }
        return session.isPaired ? .confirmedPaired : .confirmedUnpaired
    }
}

protocol AppleWatchPairingReading: Sendable {
    func pairingReadForCopy() -> AppleWatchPairingRead
}

/// Pure mapping for unit tests — keep recoverable copy ≤ a few seconds to read.
enum AppleStartHandoffCopy {
    private static let failureMessages: [AppleStartHandoffFailureCode: String] = [
        .watchNotReachable: "Apple Watch not reachable — unlock watch, open AmakaFlowWatch, keep iPhone nearby.",
        .watchAppNotInstalled: "AmakaFlowWatch not installed — install the watch app from the Watch app on iPhone.",
        .sessionNotAvailable: "Watch connectivity unavailable — restart both apps and try again.",
        .encodingFailed: "Could not encode workout for Watch — edit structure and retry.",
        .watchDecodeFailed: "Watch could not read workout — simplify intervals and retry.",
        .authorizationDenied: "Workout permission denied — Settings → Health → Data Access → AmakaFlow, allow Workouts.",
        .iosVersionUnsupported: "Requires iOS 18 to schedule in the Workout app — update iPhone and retry.",
        .emptyWorkout: "Workout has no steps — add exercises or intervals in Edit, then retry."
    ]

    private static func messageWithOptionalDetail(prefix: String, detail: String?, fallback: String) -> String {
        if let detail, !detail.isEmpty {
            return "\(prefix) — \(detail)"
        }
        return "\(prefix) — \(fallback)"
    }

    static func failureMessage(code: AppleStartHandoffFailureCode, detail: String? = nil) -> String {
        switch code {
        case .watchSendFailed:
            return messageWithOptionalDetail(
                prefix: "Watch send failed",
                detail: detail,
                fallback: "confirm AmakaFlowWatch is open, then retry."
            )
        case .conversionFailed:
            return messageWithOptionalDetail(
                prefix: "WorkoutKit conversion failed",
                detail: detail,
                fallback: "check intervals use supported step types."
            )
        case .unknown:
            return messageWithOptionalDetail(
                prefix: "Apple try failed",
                detail: detail,
                fallback: "check Watch pairing and retry."
            )
        default:
            return failureMessages[code]
                ?? messageWithOptionalDetail(
                    prefix: "Apple try failed",
                    detail: detail,
                    fallback: "check Watch pairing and retry."
                )
        }
    }

    static func sentToWatchMessage(workoutName: String) -> AppleStartHandoffResult {
        AppleStartHandoffResult(
            kind: .sentToWatch,
            message: "Sent to Apple Watch — open AmakaFlowWatch to start \"\(workoutName)\"."
        )
    }

    static func savedToFitnessMessage(workoutName: String) -> AppleStartHandoffResult {
        scheduledInWorkoutMessage(workoutName: workoutName, pairing: .unknown)
    }

    static func scheduledInWorkoutMessage(
        workoutName: String,
        pairing: AppleWatchPairingRead
    ) -> AppleStartHandoffResult {
        switch pairing {
        case .confirmedUnpaired:
            return AppleStartHandoffResult(
                kind: .savedToFitness,
                message: "Scheduled in Workout — pair an Apple Watch to run \"\(workoutName)\"."
            )
        case .confirmedPaired, .unknown:
            return AppleStartHandoffResult(
                kind: .savedToFitness,
                message: "Scheduled in Workout — open the Workout app on your Apple Watch for \"\(workoutName)\"."
            )
        }
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

struct LiveAppleWatchPairingReader: AppleWatchPairingReading {
    func pairingReadForCopy() -> AppleWatchPairingRead {
        guard WCSession.isSupported() else { return .unknown }
        return AppleWatchPairingRead.resolve(from: LiveWatchSession.shared)
    }
}

/// Coordinates WorkoutKit save for Start → Apple try.
@MainActor
final class AppleStartHandoffService {
    private let pairingReader: any AppleWatchPairingReading
    private let workoutKitSaver: (any WorkoutKitSaving)?
    private let forceFailureCode: (() -> AppleStartHandoffFailureCode?)?

    init(
        pairingReader: any AppleWatchPairingReading = LiveAppleWatchPairingReader(),
        workoutKitSaver: (any WorkoutKitSaving)?? = .some(nil),
        forceFailureCode: (() -> AppleStartHandoffFailureCode?)? = nil
    ) {
        self.pairingReader = pairingReader
        switch workoutKitSaver {
        case .some(let saver?):
            self.workoutKitSaver = saver
        case .some(nil):
            if #available(iOS 18.0, *) {
                self.workoutKitSaver = LiveWorkoutKitSaver()
            } else {
                self.workoutKitSaver = nil
            }
        case .none:
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

    func handoff(workout: Workout) async -> AppleStartHandoffResult {
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

        guard let workoutKitSaver else {
            return AppleStartHandoffResult(
                kind: .blocked,
                message: AppleStartHandoffCopy.failureMessage(code: .iosVersionUnsupported)
            )
        }

        do {
            try await workoutKitSaver.saveToWorkoutKit(workout)
            return AppleStartHandoffCopy.scheduledInWorkoutMessage(
                workoutName: workout.name,
                pairing: pairingReader.pairingReadForCopy()
            )
        } catch {
            let code = AppleStartHandoffCopy.failureCode(from: error)
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(
                    code: code,
                    detail: error.localizedDescription
                )
            )
        }
    }
}
