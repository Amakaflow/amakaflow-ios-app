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
        self.workoutKitSaver = Self.resolveWorkoutKitSaver(workoutKitSaver)
        self.scheduleCapReader = Self.resolveScheduleCapReader(scheduleCapReader)
        self.incompleteScheduleReplacer = Self.resolveIncompleteScheduleReplacer(
            incompleteScheduleReplacer
        )
        self.forceFailureCode = forceFailureCode ?? Self.defaultForceFailureCode
    }

    private static func resolveWorkoutKitSaver(
        _ override: WorkoutKitSaverOverride
    ) -> (any WorkoutKitSaving)? {
        switch override {
        case .injected(let saver):
            return saver
        case .automatic:
            if #available(iOS 18.0, *) {
                return LiveWorkoutKitSaver()
            }
            return nil
        case .disabled:
            return nil
        }
    }

    private static func resolveScheduleCapReader(
        _ override: ScheduleCapReaderOverride
    ) -> (any ScheduleCapReading)? {
        switch override {
        case .injected(let reader):
            return reader
        case .automatic:
            #if canImport(WorkoutKit)
            if #available(iOS 18.0, *) {
                return LiveScheduleCapReader()
            }
            #endif
            return nil
        case .disabled:
            return nil
        }
    }

    private static func resolveIncompleteScheduleReplacer(
        _ override: IncompleteScheduleReplacerOverride
    ) -> (any IncompleteScheduleReplacing)? {
        switch override {
        case .injected(let replacer):
            return replacer
        case .automatic:
            #if canImport(WorkoutKit)
            if #available(iOS 18.0, *) {
                return LiveIncompleteScheduleReplacer()
            }
            #endif
            return nil
        case .disabled:
            return nil
        }
    }

    private static func defaultForceFailureCode() -> AppleStartHandoffFailureCode? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["UITEST_APPLE_TRY_FAIL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return AppleStartHandoffFailureCode(rawValue: raw) ?? .unknown
        }
        #endif
        return nil
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
            var effectiveCount = status.scheduledCount
            // AMA-2367 — a matching incomplete plan frees a slot on confirm; don't
            // hard-block prepare when replacement would make room.
            if effectiveCount >= status.maxAllowedCount, let incompleteScheduleReplacer {
                do {
                    let replacements = try await incompleteScheduleReplacer.findIncompletePlans(
                        titled: workout.name
                    )
                    effectiveCount -= replacements.count
                } catch {
                    return AppleStartHandoffResult(
                        kind: .failed,
                        message: AppleStartHandoffCopy.failureMessage(
                            code: .unknown,
                            detail: error.localizedDescription
                        )
                    )
                }
            }
            if effectiveCount >= status.maxAllowedCount {
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
            // AMA-2367 — discover replacements first; remove only after a successful save.
            var replacements: [WorkoutScheduleRow] = []
            if let incompleteScheduleReplacer {
                replacements = try await incompleteScheduleReplacer.findIncompletePlans(
                    titled: workoutName
                )
            }
            if let scheduleCapReader {
                let status = await scheduleCapReader.scheduleCapStatus()
                let effectiveCount = status.scheduledCount - replacements.count
                if effectiveCount >= status.maxAllowedCount {
                    return AppleStartHandoffResult(
                        kind: .failed,
                        message: AppleStartHandoffCopy.failureMessage(code: .scheduleCapReached),
                        showsManageScheduledPlans: true
                    )
                }
            }
            try await workoutKitSaver.saveMapperPlanJSON(planJSON)
            if let incompleteScheduleReplacer, !replacements.isEmpty {
                await incompleteScheduleReplacer.remove(rows: replacements)
            }
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
