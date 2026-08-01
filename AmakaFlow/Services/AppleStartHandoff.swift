//
//  AppleStartHandoff.swift
//  AmakaFlow
//
//  AMA-2287: WorkoutKit-primary Start → Workout on Apple Watch.
//

import Foundation
import WatchConnectivity
import WorkoutKitSync
#if canImport(WorkoutKit)
import WorkoutKit
#endif

/// Outcome of Start → Apple for in-app status copy (seconds, not minutes).
struct AppleStartHandoffResult: Equatable {
    enum Kind: Equatable {
        case sentToWatch
        case savedToFitness
        case failed
        case blocked
        /// Mapper DTO ready — UI shows preview before scheduling (AMA-2351).
        case previewReady
    }

    let kind: Kind
    /// User-facing status line shown under detail actions.
    let message: String
    /// AMA-2330 P1 fix: true for a successful schedule (`.savedToFitness`) *or* a
    /// `.scheduleCapReached` failure — both land the user at the same "Manage
    /// scheduled plans" entry point, since clearing space there is the fix either way.
    let showsManageScheduledPlans: Bool
    /// AMA-2351 — composition line for preview / post-schedule status.
    let compositionLine: String?
    let planMeta: WorkoutKitPlanMeta?
    let planJSON: Data?

    init(
        kind: Kind,
        message: String,
        showsManageScheduledPlans: Bool = false,
        compositionLine: String? = nil,
        planMeta: WorkoutKitPlanMeta? = nil,
        planJSON: Data? = nil
    ) {
        self.kind = kind
        self.message = message
        self.showsManageScheduledPlans = showsManageScheduledPlans
        self.compositionLine = compositionLine
        self.planMeta = planMeta
        self.planJSON = planJSON
    }
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
    /// AMA-2330: preflight hit before saving — the Workout app's own schedule is full.
    case scheduleCapReached = "schedule_cap_reached"
    /// AMA-2351: mapper/BFF compose or re-validation failed — never silent no-schedule.
    case mapperComposeFailed = "mapper_compose_failed"
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

/// Outcome of a single WatchConnectivity send attempt.
enum WatchWorkoutSendOutcome: Equatable {
    case sent
    case failed(WatchConnectivityError)
    case watchRejected(String)
}

/// Test seam for WorkoutKit saves without linking WorkoutKit in unit tests.
/// AMA-2351: saves mapper JSON via WorkoutKitSync — no on-device block interpretation.
protocol WorkoutKitSaving: Sendable {
    func saveMapperPlanJSON(_ data: Data) async throws
}

/// AMA-2367 — remove incomplete same-title plans before adding a new schedule.
protocol IncompleteScheduleReplacing: Sendable {
    func removeIncompletePlans(titled title: String) async
}

#if canImport(WorkoutKit)
@available(iOS 18.0, *)
struct LiveIncompleteScheduleReplacer: IncompleteScheduleReplacing {
    func removeIncompletePlans(titled title: String) async {
        let needle = Self.normalizedTitle(title)
        guard !needle.isEmpty else { return }
        let scheduler = LiveWorkoutKitScheduler()
        guard let rows = try? await scheduler.fetchScheduledRows() else { return }
        for row in rows where !row.isComplete {
            guard Self.normalizedTitle(row.title) == needle else { continue }
            await scheduler.remove(row: row)
        }
    }

    static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
#endif

enum IncompleteScheduleReplacerOverride {
    case automatic
    case injected(any IncompleteScheduleReplacing)
    case disabled
}

@available(iOS 18.0, *)
struct LiveWorkoutKitSaver: WorkoutKitSaving {
    func saveMapperPlanJSON(_ data: Data) async throws {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw WorkoutPlanError.invalidJSONString
        }
        try await WorkoutKitSync.default.parseAndSave(from: jsonString)
    }
}

struct LiveAppleWatchPairingReader: AppleWatchPairingReading {
    func pairingReadForCopy() -> AppleWatchPairingRead {
        guard WCSession.isSupported() else { return .unknown }
        return AppleWatchPairingRead.resolve(from: LiveWatchSession.shared)
    }
}

/// AMA-2330: test seam for the at-cap preflight in `handoff(workout:)` — avoids
/// linking WorkoutKit's `WorkoutScheduler` directly in unit tests. Non-throwing
/// to mirror `WorkoutScheduler`'s own (non-throwing) `scheduledWorkouts` API.
protocol ScheduleCapReading: Sendable {
    func scheduleCapStatus() async -> (scheduledCount: Int, maxAllowedCount: Int)
}

#if canImport(WorkoutKit)
@available(iOS 18.0, *)
struct LiveScheduleCapReader: ScheduleCapReading {
    func scheduleCapStatus() async -> (scheduledCount: Int, maxAllowedCount: Int) {
        let count = await WorkoutScheduler.shared.scheduledWorkouts.count
        return (count, WorkoutScheduler.maxAllowedScheduledWorkoutCount)
    }
}
#endif

/// How `AppleStartHandoffService` obtains a WorkoutKit saver — avoids nested-optional ambiguity.
enum WorkoutKitSaverOverride {
    /// Use `LiveWorkoutKitSaver` on iOS 18+; otherwise no saver (blocked).
    case automatic
    /// Inject a test/production double.
    case injected(any WorkoutKitSaving)
    /// Force no saver (blocked / iOS-unsupported path in tests).
    case disabled
}

/// How `AppleStartHandoffService` obtains its at-cap preflight reader.
///
/// Defaults to `.disabled` — unlike `WorkoutKitSaverOverride`, every existing
/// call site of this initializer predates this parameter, so an `.automatic`
/// default here would silently start exercising live WorkoutKit APIs inside
/// existing unit tests that never asked for it. The one production call site
/// (`UnifiedWorkoutDetailView.beginAppleTryHandoff`) opts in explicitly with
/// `.automatic`.
enum ScheduleCapReaderOverride {
    /// Use `LiveScheduleCapReader` on iOS 18+; otherwise no reader (no preflight).
    case automatic
    /// Inject a test/production double.
    case injected(any ScheduleCapReading)
    /// Never preflight (default — safe for tests that don't care about the cap).
    case disabled
}

/// Coordinates mapper compose → preview → WorkoutKit schedule for Start → Apple.
@MainActor
final class AppleStartHandoffService {
    private let pairingReader: any AppleWatchPairingReading
    private let workoutKitSaver: (any WorkoutKitSaving)?
    private let planProvider: (any WorkoutKitPlanProviding)?
    private let scheduleCapReader: (any ScheduleCapReading)?
    private let incompleteScheduleReplacer: (any IncompleteScheduleReplacing)?
    private let forceFailureCode: (() -> AppleStartHandoffFailureCode?)?

    init(
        pairingReader: any AppleWatchPairingReading = LiveAppleWatchPairingReader(),
        workoutKitSaver: WorkoutKitSaverOverride = .automatic,
        planProvider: (any WorkoutKitPlanProviding)? = nil,
        scheduleCapReader: ScheduleCapReaderOverride = .disabled,
        incompleteScheduleReplacer: IncompleteScheduleReplacerOverride = .disabled,
        forceFailureCode: (() -> AppleStartHandoffFailureCode?)? = nil
    ) {
        self.pairingReader = pairingReader
        self.planProvider = planProvider
        switch workoutKitSaver {
        case .injected(let saver):
            self.workoutKitSaver = saver
        case .automatic:
            if #available(iOS 18.0, *) {
                self.workoutKitSaver = LiveWorkoutKitSaver()
            } else {
                self.workoutKitSaver = nil
            }
        case .disabled:
            self.workoutKitSaver = nil
        }
        switch scheduleCapReader {
        case .injected(let reader):
            self.scheduleCapReader = reader
        case .automatic:
            #if canImport(WorkoutKit)
            if #available(iOS 18.0, *) {
                self.scheduleCapReader = LiveScheduleCapReader()
            } else {
                self.scheduleCapReader = nil
            }
            #else
            self.scheduleCapReader = nil
            #endif
        case .disabled:
            self.scheduleCapReader = nil
        }
        switch incompleteScheduleReplacer {
        case .injected(let replacer):
            self.incompleteScheduleReplacer = replacer
        case .automatic:
            #if canImport(WorkoutKit)
            if #available(iOS 18.0, *) {
                self.incompleteScheduleReplacer = LiveIncompleteScheduleReplacer()
            } else {
                self.incompleteScheduleReplacer = nil
            }
            #else
            self.incompleteScheduleReplacer = nil
            #endif
        case .disabled:
            self.incompleteScheduleReplacer = nil
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

    /// Fetch mapper DTO for preview. Does not schedule.
    func prepare(workout: Workout) async -> AppleStartHandoffResult {
        if let forced = forceFailureCode?() {
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(code: forced),
                showsManageScheduledPlans: forced == .scheduleCapReached
            )
        }

        guard workoutKitSaver != nil else {
            return AppleStartHandoffResult(
                kind: .blocked,
                message: AppleStartHandoffCopy.failureMessage(code: .iosVersionUnsupported)
            )
        }

        guard let planProvider else {
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(
                    code: .mapperComposeFailed,
                    detail: "WorkoutKit plan provider is not configured."
                )
            )
        }

        if let scheduleCapReader {
            let status = await scheduleCapReader.scheduleCapStatus()
            if status.scheduledCount >= status.maxAllowedCount {
                return AppleStartHandoffResult(
                    kind: .failed,
                    message: AppleStartHandoffCopy.failureMessage(code: .scheduleCapReached),
                    showsManageScheduledPlans: true
                )
            }
        }

        do {
            let data = try await planProvider.fetchMapperPlanJSON(for: workout)
            let meta = WorkoutKitPlanMeta(fromMapperJSON: data)
            let dto = try WorkoutKitSync.default.parse(from: data)
            guard !dto.intervals.isEmpty else {
                return AppleStartHandoffResult(
                    kind: .failed,
                    message: AppleStartHandoffCopy.failureMessage(code: .emptyWorkout)
                )
            }
            let line = WorkoutKitRoutingCopy.compositionLine(meta: meta)
            return AppleStartHandoffResult(
                kind: .previewReady,
                message: line,
                compositionLine: line,
                planMeta: meta,
                planJSON: data
            )
        } catch {
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(
                    code: .mapperComposeFailed,
                    detail: error.localizedDescription
                )
            )
        }
    }

    /// Schedule a previously prepared mapper plan JSON.
    func confirmSchedule(workoutName: String, planJSON: Data, meta: WorkoutKitPlanMeta) async -> AppleStartHandoffResult {
        guard let workoutKitSaver else {
            return AppleStartHandoffResult(
                kind: .blocked,
                message: AppleStartHandoffCopy.failureMessage(code: .iosVersionUnsupported)
            )
        }
        do {
            // AMA-2367 — replace incomplete same-title plans so Start again does not stack.
            if let incompleteScheduleReplacer {
                await incompleteScheduleReplacer.removeIncompletePlans(titled: workoutName)
            }
            try await workoutKitSaver.saveMapperPlanJSON(planJSON)
            return AppleStartHandoffCopy.scheduledInWorkoutMessage(
                workoutName: workoutName,
                pairing: pairingReader.pairingReadForCopy(),
                compositionLine: WorkoutKitRoutingCopy.compositionLine(meta: meta)
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

    /// One-shot compose + schedule (tests / callers that skip the preview sheet).
    func handoff(workout: Workout) async -> AppleStartHandoffResult {
        let prepared = await prepare(workout: workout)
        guard prepared.kind == .previewReady,
              let planJSON = prepared.planJSON,
              let meta = prepared.planMeta else {
            return prepared
        }
        return await confirmSchedule(
            workoutName: workout.name,
            planJSON: planJSON,
            meta: meta
        )
    }
}
