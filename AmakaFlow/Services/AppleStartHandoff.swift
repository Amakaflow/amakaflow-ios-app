//
//  AppleStartHandoff.swift
//  AmakaFlow
//
//  AMA-2287: WorkoutKit-primary Start → Workout on Apple Watch.
//

// swiftlint:disable file_length
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

extension AppleStartHandoffResult.Kind {
    /// AMA-2371 final review I4 — mirrors
    /// `GarminHandoffRecord.Outcome.isTerminalGarminSentCardSuccess`. Both
    /// `.savedToFitness` (scheduled in Workout) and `.sentToWatch` (pushed
    /// straight to the watch) are terminal Apple successes that should show
    /// the detail screen's lime "Scheduled on Apple Watch" card; `.failed`,
    /// `.blocked`, and `.previewReady` (still mid-flow) must not.
    var isTerminalAppleSentCardSuccess: Bool {
        switch self {
        case .savedToFitness, .sentToWatch: return true
        case .failed, .blocked, .previewReady: return false
        }
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
final class AppleStartHandoffService { // swiftlint:disable:this type_body_length
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
        if let raw = ProcessInfo.processInfo.environment["AF_FAULT_APPLE_START_FAIL"]?
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
    /// - Parameter libraryWorkoutID: AmakaFlow Library id — persisted beside the
    ///   WorkoutKit planID so Watch Item Open workout never routes a plan UUID.
    func confirmSchedule(
        workoutName: String,
        planJSON: Data,
        meta: WorkoutKitPlanMeta,
        libraryWorkoutID: String? = nil
    ) async -> AppleStartHandoffResult {
        // Serialize confirms so a double-tap cannot race two saves before
        // same-title incomplete replacement runs (stacked duplicates).
        await AppleScheduleConfirmGate.shared.run {
            await self.confirmScheduleUnlocked(
                workoutName: workoutName,
                planJSON: planJSON,
                meta: meta,
                libraryWorkoutID: libraryWorkoutID
            )
        }
    }

    private func confirmScheduleUnlocked(
        workoutName: String,
        planJSON: Data,
        meta: WorkoutKitPlanMeta,
        libraryWorkoutID: String?
    ) async -> AppleStartHandoffResult {
        guard let workoutKitSaver else {
            return AppleStartHandoffResult(
                kind: .blocked,
                message: AppleStartHandoffCopy.failureMessage(code: .iosVersionUnsupported)
            )
        }
        do {
            // Same display name → replace incomplete plans. Intentional copies
            // (`Name (1)`) only match that exact title, so they can coexist.
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
            let preSaveIDs = Set(replacements.map(\.id.planID))
            if let incompleteScheduleReplacer {
                if !replacements.isEmpty {
                    await incompleteScheduleReplacer.remove(rows: replacements)
                }
                // Identify the plan(s) that appeared from this confirm (not in the
                // pre-save set). Prefer that identity over schedule-time heuristics
                // so a raced duplicate with a later date cannot displace the save.
                // Lookup failures must surface — do not report clean success when
                // duplicate cleanup could not run (AMA-2394 / CodeRabbit).
                let afterSave = try await incompleteScheduleReplacer.findIncompletePlans(
                    titled: workoutName
                )
                let newlyAppeared = afterSave.filter { !preSaveIDs.contains($0.id.planID) }
                // `min(by:)` matches preferred-first order (same as sorted().first).
                let savedPlanID = newlyAppeared
                    .min(by: IncompleteScheduleReplacerKeeper.isPreferredOrder)?
                    .id.planID
                try await incompleteScheduleReplacer.removeDuplicateIncompletePlans(
                    titled: workoutName,
                    keepingPlanID: savedPlanID,
                    excluding: preSaveIDs
                )
            }
            if let libraryWorkoutID {
                await recordPlanLink(
                    workoutName: workoutName,
                    libraryWorkoutID: libraryWorkoutID,
                    planJSON: planJSON,
                    excludedPlanIDs: preSaveIDs
                )
            }
            NotificationCenter.default.post(name: .appleWatchScheduleDidChange, object: nil)
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

    /// After a successful schedule, bind the new WorkoutKit planID to the Library workout.
    /// Excludes plan IDs we intended to replace so a failed/no-op removal cannot
    /// bind the Library id to a stale leftover row.
    private func recordPlanLink(
        workoutName: String,
        libraryWorkoutID: String,
        planJSON: Data,
        excludedPlanIDs: Set<String>
    ) async {
        guard let incompleteScheduleReplacer else { return }
        guard let rows = try? await incompleteScheduleReplacer.findIncompletePlans(titled: workoutName)
        else { return }
        let candidates = rows.filter { !excludedPlanIDs.contains($0.id.planID) }
        guard let newest = candidates.first else { return }
        AppleScheduledWorkoutLinkStore.shared.record(
            planID: newest.id.planID,
            workoutID: libraryWorkoutID,
            title: workoutName,
            planJSON: planJSON
        )
        // AMA-2390 — stamp Watch Item readiness from the scheduled plan so the
        // sheet mirrors what landed (not standing WorkoutPreferences.defaults).
        Self.stampWatchItemReadiness(
            workoutID: libraryWorkoutID,
            planJSON: planJSON
        )
    }

    /// Persist delivered/draft readiness from composed planJSON (MainActor store).
    @MainActor
    private static func stampWatchItemReadiness(workoutID: String, planJSON: Data) {
        let sections = WorkoutKitPlanStepSummary.sections(from: planJSON)
        let readiness = WatchItemViewModel.readinessReflectingDelivered(sections)
        let config = WatchItemViewModel.configReflectingDelivered(sections)
        let pills = WatchItemViewModel.pills(
            from: readiness,
            config: config,
            isApple: true,
            title: "",
            deliveredStepTotal: sections.reduce(0) { $0 + $1.steps.count }
        )
        let snapshot = WatchItemReadinessSnapshot(
            readiness: readiness,
            config: config,
            snapshotPills: pills,
            updatedAt: Date()
        )
        WatchItemReadinessStore.shared.saveDelivered(workoutID: workoutID, snapshot: snapshot)
        WatchItemReadinessStore.shared.saveDraft(workoutID: workoutID, snapshot: snapshot)
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
            meta: meta,
            libraryWorkoutID: workout.id
        )
    }
}

/// Serializes Apple WorkoutKit schedule confirms on the main actor.
/// MainActor alone is not enough — concurrent Tasks interleave at `await` points.
@MainActor
final class AppleScheduleConfirmGate {
    static let shared = AppleScheduleConfirmGate()
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T>(_ operation: () async -> T) async -> T {
        while isBusy {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        isBusy = true
        defer {
            isBusy = false
            if !waiters.isEmpty {
                waiters.removeFirst().resume()
            }
        }
        return await operation()
    }
}
