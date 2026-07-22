//
//  GarminStartHandoff.swift
//  AmakaFlow
//
//  AMA-2286: Library → Start → Garmin one-tap push via CIQ queue (not garth).
//

import Foundation

/// Outcome of Start → Garmin for in-app status copy (seconds, not minutes).
struct GarminStartHandoffResult: Equatable {
    enum Kind: Equatable {
        case queued
        case sent
        case readyOnWatch
        case failed
    }

    let kind: Kind
    /// User-facing status line shown under detail actions.
    let message: String
}

enum GarminStartHandoffFailureCode: String, Equatable {
    case notPaired = "not_paired"
    case auth = "auth"
    case emptyConverter = "empty_converter"
    case fitTooLarge = "fit_too_large"
    case storageFull = "storage_full"
    case unknown = "unknown"
}

/// Pure mapping for unit tests — keep recoverable copy ≤ a few seconds to read.
enum GarminStartHandoffCopy {
    /// AMA-2310: Start sheet subtitle when Garmin is not paired (tappable recovery).
    static let unpairedRecoverySubtitle = "Tap to pair CIQ / open Devices"

    /// AMA-2310: Start sheet tag when Garmin needs pairing.
    static let unpairedRecoveryTag = "PAIR"

    /// Status under detail after unpaired Garmin tap (matches not_paired what+why).
    static var unpairedRecoveryStatusMessage: String {
        failureMessage(code: .notPaired)
    }

    static func failureMessage(code: GarminStartHandoffFailureCode, detail: String? = nil) -> String {
        switch code {
        case .notPaired:
            return "Garmin not paired — open Profile → Devices and enter the code from your CIQ widget."
        case .auth:
            return "Sign-in expired — sign in again, then retry Start → Garmin."
        case .emptyConverter:
            return "Workout has no exportable exercises — add sets/reps or intervals, then retry."
        case .fitTooLarge:
            return "FIT too large for watch download — shorten the workout, then retry."
        case .storageFull:
            return "Watch storage full — delete old AmakaFlow workouts on the watch, then retry."
        case .unknown:
            if let detail, !detail.isEmpty {
                return "Garmin push failed — \(detail)"
            }
            return "Garmin push failed — check pairing and try again."
        }
    }

    static func successMessage(state: Components.Schemas.WatchDeliveryState?, gymTitle: String) -> GarminStartHandoffResult {
        switch state {
        case .confirmedOnDevice:
            return GarminStartHandoffResult(
                kind: .readyOnWatch,
                message: "Ready on watch — open native player (\(gymTitle))."
            )
        case .fetchedByWidget:
            return GarminStartHandoffResult(
                kind: .readyOnWatch,
                message: "Loaded on watch — confirm in CIQ widget to start (\(gymTitle))."
            )
        case .pushed:
            return GarminStartHandoffResult(
                kind: .sent,
                message: "Sent to Garmin — open AmakaFlow CIQ widget to download (\(gymTitle))."
            )
        case .generated, .failed, .none:
            return GarminStartHandoffResult(
                kind: .queued,
                message: "Queued for Garmin — open CIQ widget when prompt appears (\(gymTitle))."
            )
        }
    }

    static func failureCode(fromHTTPStatus status: Int, detail: String?) -> GarminStartHandoffFailureCode {
        let lowered = (detail ?? "").lowercased()
        if status == 401 {
            return .auth
        }
        if status == 422 {
            if lowered.contains("empty_converter") {
                return .emptyConverter
            }
            if lowered.contains("fit_too_large") {
                return .fitTooLarge
            }
            if lowered.contains("storage") {
                return .storageFull
            }
            if lowered.contains("paired") || lowered.contains("no paired garmin") {
                return .notPaired
            }
        }
        if lowered.contains("storage") {
            return .storageFull
        }
        return .unknown
    }

    static func failureCode(fromAPIError error: Error) -> GarminStartHandoffFailureCode {
        let cta = CTAError.map(error)
        switch cta {
        case .unauthenticated:
            return .auth
        case .http(let status, let body, _):
            let detail = Self.detailString(from: body)
            return failureCode(fromHTTPStatus: status, detail: detail)
        default:
            return .unknown
        }
    }

    private static func detailString(from body: String?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        if let detail = CTAError.extractField("detail", from: body) {
            return detail
        }
        return body
    }
}

/// Coordinates Clerk first-push + optional status poll for Start → Garmin.
@MainActor
final class GarminStartHandoffService {
    private let apiService: APIServiceProviding
    private let forceFailureCode: (() -> GarminStartHandoffFailureCode?)?

    init(
        apiService: APIServiceProviding? = nil,
        forceFailureCode: (() -> GarminStartHandoffFailureCode?)? = nil
    ) {
        self.apiService = apiService ?? AppDependencies.current.apiService
        self.forceFailureCode = forceFailureCode ?? {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["UITEST_GARMIN_PUSH_FAIL"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                return GarminStartHandoffFailureCode(rawValue: raw)
                    ?? .unknown
            }
            #endif
            return nil
        }
    }

    func push(workoutId: String, gymTitle: String) async -> GarminStartHandoffResult {
        if let forced = forceFailureCode?() {
            return GarminStartHandoffResult(
                kind: .failed,
                message: GarminStartHandoffCopy.failureMessage(code: forced)
            )
        }

        do {
            let pushResult = try await apiService.pushWatchDelivery(workoutId: workoutId)
            guard pushResult.success else {
                return GarminStartHandoffResult(
                    kind: .failed,
                    message: GarminStartHandoffCopy.failureMessage(code: .unknown, detail: "server rejected push")
                )
            }

            // Best-effort status enrich; push success alone is enough for queued/sent UX.
            if let status = try? await apiService.watchDeliveryStatus(workoutId: workoutId) {
                return GarminStartHandoffCopy.successMessage(state: status.state, gymTitle: gymTitle)
            }
            return GarminStartHandoffCopy.successMessage(state: .pushed, gymTitle: gymTitle)
        } catch {
            let code = GarminStartHandoffCopy.failureCode(fromAPIError: error)
            let detail: String?
            if case let .http(_, body, _) = CTAError.map(error) {
                detail = body.flatMap { CTAError.extractField("detail", from: $0) } ?? body
            } else {
                detail = error.localizedDescription
            }
            return GarminStartHandoffResult(
                kind: .failed,
                message: GarminStartHandoffCopy.failureMessage(code: code, detail: detail)
            )
        }
    }
}
