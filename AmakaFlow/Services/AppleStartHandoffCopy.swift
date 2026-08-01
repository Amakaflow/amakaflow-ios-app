//
//  AppleStartHandoffCopy.swift
//  AmakaFlow
//
//  AMA-2287: user-facing copy + failure mapping for Start → Apple.
//

import Foundation
import WorkoutKitSync

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
        .emptyWorkout: "Workout has no steps — add exercises or intervals in Edit, then retry.",
        .scheduleCapReached:
            "Workout app schedule is full — open Manage scheduled plans (Devices → Scheduled in Workout) "
                + "to remove old plans, then retry.",
        .mapperComposeFailed:
            "Could not build Apple Workout plan — check connection and workout structure, then retry."
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
        case .mapperComposeFailed:
            return messageWithOptionalDetail(
                prefix: "Could not build Apple Workout plan",
                detail: detail,
                fallback: "check connection and workout structure, then retry."
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
        pairing: AppleWatchPairingRead,
        compositionLine: String? = nil
    ) -> AppleStartHandoffResult {
        let compositionSuffix: String = {
            guard let compositionLine, !compositionLine.isEmpty else { return "" }
            return " \(compositionLine)."
        }()
        switch pairing {
        case .confirmedUnpaired:
            return AppleStartHandoffResult(
                kind: .savedToFitness,
                message: "Scheduled in Workout — pair an Apple Watch to run \"\(workoutName)\".\(compositionSuffix)",
                showsManageScheduledPlans: true,
                compositionLine: compositionLine
            )
        case .confirmedPaired, .unknown:
            return AppleStartHandoffResult(
                kind: .savedToFitness,
                message: "Scheduled in Workout — open the Workout app on your Apple Watch for \"\(workoutName)\".\(compositionSuffix)",
                showsManageScheduledPlans: true,
                compositionLine: compositionLine
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
