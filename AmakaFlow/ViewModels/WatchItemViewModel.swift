//
//  WatchItemViewModel.swift
//  AmakaFlow
//
//  AMA-2386 / AMA-2388: sheet state — readiness draft, AMA-2378 configurators,
//  always-visible replace CTA, shared store seed/persist, library link.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class WatchItemViewModel: ObservableObject {
    let device: WatchItemDevice
    /// Library workout id when linked; may equal planID only in legacy/demo.
    let workoutID: String
    let title: String
    let stateLine: String
    let applePlanID: String?
    let appleDateComponents: DateComponents?
    let garminState: GarminQueueItemState?
    let warmupExerciseNames: [String]
    /// Linked Library workout title for the FROM YOUR LIBRARY row; nil = unlinked.
    let libraryWorkoutTitle: String?
    let libraryWorkoutID: String?

    @Published private(set) var tracker: WatchItemChangeTracker
    @Published private(set) var snapshotPills: [String]
    @Published private(set) var isReplacing = false
    @Published private(set) var justReplaced = false
    @Published private(set) var stepSections: [PreviewSection]
    @Published var lastError: String?
    @Published var showingStepsOverlay = false

    private let replacer: any WatchItemReplacing
    private let toast: DDToastCenter
    private let readinessStore: any WatchItemReadinessStoring
    private let prefsPersister: WatchItemPrefsPersisting?

    var isApple: Bool { device.isApple }
    var changeCount: Int { tracker.changeCount }
    var hasChanges: Bool { tracker.hasChanges }
    var isLinkedToLibrary: Bool { libraryWorkoutID != nil }
    var stepCount: Int {
        let fromPills = snapshotPills.first.flatMap { pill -> Int? in
            let digits = pill.prefix(while: \.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }
        if let fromPills { return fromPills }
        return stepSections.reduce(0) { $0 + $1.steps.count }
    }

    var mobilityEnabled: Bool { tracker.draft.mobilityEnabled }
    var warmupsEnabled: Bool { tracker.draft.warmupsEnabled }
    var restEnabled: Bool { tracker.draft.restEnabled }
    var cooldownEnabled: Bool { tracker.draft.cooldownEnabled }

    var mobilityActivities: [EnrichmentActivityPref] {
        get { tracker.draftConfig.mobilityActivities }
        set { mutateConfig { $0.mobilityActivities = newValue } }
    }

    var cooldownActivities: [EnrichmentActivityPref] {
        get { tracker.draftConfig.cooldownActivities }
        set { mutateConfig { $0.cooldownActivities = newValue } }
    }

    var perExerciseRamps: [PerExerciseRamp] {
        get { tracker.draftConfig.perExerciseRamps }
        set { mutateConfig { $0.perExerciseRamps = newValue } }
    }

    var restOpen: Bool {
        get { tracker.draftConfig.restOpen }
        set { mutateConfig { $0.restOpen = newValue } }
    }

    var restSec: Int {
        get { tracker.draftConfig.restSec }
        set {
            mutateConfig {
                $0.restSec = WorkoutEnrichmentPushCopy.normalizedRestSec(newValue)
            }
        }
    }

    private func mutateConfig(_ body: (inout WatchItemConfigState) -> Void) {
        var next = tracker
        next.updateConfig(body)
        tracker = next
        justReplaced = false
        persistDraft()
    }

    var enrichmentTarget: EnrichmentPushTarget {
        isApple ? .apple : .garmin
    }

    init(
        device: WatchItemDevice,
        workoutID: String,
        title: String,
        stateLine: String,
        snapshotPills: [String],
        baseline: WatchItemReadinessState,
        config: WatchItemConfigState,
        draft: WatchItemReadinessState? = nil,
        draftConfig: WatchItemConfigState? = nil,
        warmupExerciseNames: [String] = [],
        applePlanID: String? = nil,
        appleDateComponents: DateComponents? = nil,
        garminState: GarminQueueItemState? = nil,
        libraryWorkoutID: String? = nil,
        libraryWorkoutTitle: String? = nil,
        stepSections: [PreviewSection] = [],
        replacer: (any WatchItemReplacing)? = nil,
        toast: DDToastCenter? = nil,
        readinessStore: (any WatchItemReadinessStoring)? = nil,
        prefsPersister: WatchItemPrefsPersisting? = nil
    ) {
        self.device = device
        self.workoutID = workoutID
        self.title = title
        self.stateLine = stateLine
        self.snapshotPills = snapshotPills
        self.warmupExerciseNames = warmupExerciseNames
        self.applePlanID = applePlanID
        self.appleDateComponents = appleDateComponents
        self.garminState = garminState
        self.libraryWorkoutID = libraryWorkoutID
        self.libraryWorkoutTitle = libraryWorkoutTitle ?? (libraryWorkoutID != nil ? title : nil)
        self.stepSections = stepSections
        var tracker = WatchItemChangeTracker(baseline: baseline, config: config)
        if let draft, let draftConfig {
            tracker = WatchItemChangeTracker(
                baseline: baseline,
                config: config,
                draft: draft,
                draftConfig: draftConfig
            )
        }
        self.tracker = tracker
        self.replacer = replacer ?? WatchItemReplaceCoordinator()
        self.toast = toast ?? DDToastCenter.shared
        self.readinessStore = readinessStore ?? WatchItemReadinessStore.shared
        self.prefsPersister = prefsPersister
    }

    func setEnabled(_ row: WatchItemReadinessRow, _ enabled: Bool) {
        guard !isReplacing else { return }
        var next = tracker
        next.setEnabled(row, enabled)
        tracker = next
        justReplaced = false
        persistDraft()
    }

    func isEdited(_ row: WatchItemReadinessRow) -> Bool {
        tracker.isChanged(row)
    }

    func mobilityBinding() -> Binding<[EnrichmentActivityPref]> {
        Binding(
            get: { self.mobilityActivities },
            set: { self.mobilityActivities = $0 }
        )
    }

    func cooldownBinding() -> Binding<[EnrichmentActivityPref]> {
        Binding(
            get: { self.cooldownActivities },
            set: { self.cooldownActivities = $0 }
        )
    }

    func rampsBinding() -> Binding<[PerExerciseRamp]> {
        Binding(
            get: { self.perExerciseRamps },
            set: { self.perExerciseRamps = $0 }
        )
    }

    func restOpenBinding() -> Binding<Bool> {
        Binding(
            get: { self.restOpen },
            set: { self.restOpen = $0 }
        )
    }

    func restSecBinding() -> Binding<Int> {
        Binding(
            get: { self.restSec },
            set: { self.restSec = $0 }
        )
    }

    func replaceCTATitle() -> String {
        if isReplacing { return WatchItemCopy.ctaUpdating }
        if justReplaced && !hasChanges { return WatchItemCopy.ctaUpToDate }
        return WatchItemCopy.replaceCTA(changeCount: changeCount)
    }

    /// CTA is always in the view — never demo-gated (AMA-2388).
    var canReplace: Bool { hasChanges && !isReplacing }

    var applyNote: String {
        WatchItemCopy.applyNote(hasChanges: hasChanges, isUpToDate: justReplaced && !hasChanges)
    }

    var onWatchLabel: String {
        justReplaced ? WatchItemCopy.onWatchUpdated : WatchItemCopy.onWatchNow
    }

    func replace() async {
        guard canReplace else { return }
        isReplacing = true
        lastError = nil
        let toastId = toast.beginPending(text: WatchItemCopy.toastPending)

        let request = WatchItemReplaceRequest(
            device: device,
            workoutID: libraryWorkoutID ?? workoutID,
            title: title,
            applePlanID: applePlanID,
            appleDateComponents: appleDateComponents
        )
        let result = await replacer.replace(request)

        switch result {
        case .success:
            var next = tracker
            next.markSucceeded()
            tracker = next
            justReplaced = true
            snapshotPills = Self.pills(from: tracker.draft, config: tracker.draftConfig, isApple: isApple, title: title)
            persistDeliveredAndDraft()
            toast.resolve(
                id: toastId,
                kind: .device,
                text: WatchItemCopy.toastSuccess(isApple: isApple)
            )
        case .failure(.cancelled):
            toast.dismissCurrent()
        case .failure(let error):
            let message = error.errorDescription ?? "Replace failed"
            lastError = message
            toast.resolve(id: toastId, kind: .error, text: message)
        }
        isReplacing = false
    }

    // MARK: - Persistence

    private var storeKey: String {
        libraryWorkoutID ?? workoutID
    }

    private func persistDraft() {
        let key = storeKey
        guard !key.isEmpty else { return }
        let snap = WatchItemReadinessSnapshot(
            readiness: tracker.draft,
            config: tracker.draftConfig,
            snapshotPills: snapshotPills,
            updatedAt: Date()
        )
        readinessStore.saveDraft(workoutID: key, snapshot: snap)
        prefsPersister?.persist(snapshot: snap)
    }

    private func persistDeliveredAndDraft() {
        let key = storeKey
        guard !key.isEmpty else { return }
        let snap = WatchItemReadinessSnapshot(
            readiness: tracker.draft,
            config: tracker.draftConfig,
            snapshotPills: snapshotPills,
            updatedAt: Date()
        )
        readinessStore.saveDelivered(workoutID: key, snapshot: snap)
        readinessStore.saveDraft(workoutID: key, snapshot: snap)
        prefsPersister?.persist(snapshot: snap)
    }

    // MARK: - Factories

    static func apple(
        row: WorkoutScheduleRow,
        calendar: Calendar = .current,
        linkStore: any AppleScheduledWorkoutLinkStoring = AppleScheduledWorkoutLinkStore.shared,
        readinessStore: any WatchItemReadinessStoring = WatchItemReadinessStore.shared,
        library: [(id: String, title: String)] = [],
        prefs: WorkoutPreferences? = nil,
        stepSections: [PreviewSection] = []
    ) -> WatchItemViewModel {
        let when = Self.appleStateLine(for: row, calendar: calendar)
        let linkedID = linkStore.resolve(planID: row.id.planID, title: row.title, library: library)
        let linkedTitle = linkedID.flatMap { id in library.first { $0.id == id }?.title } ?? (linkedID != nil ? row.title : nil)
        let storeKey = linkedID ?? row.id.planID
        let seeded = Self.seed(
            storeKey: storeKey,
            title: row.title,
            isApple: true,
            prefs: prefs,
            readinessStore: readinessStore
        )
        return WatchItemViewModel(
            device: .apple,
            workoutID: storeKey,
            title: row.title,
            stateLine: when,
            snapshotPills: seeded.pills,
            baseline: seeded.baseline,
            config: seeded.baselineConfig,
            draft: seeded.draft,
            draftConfig: seeded.draftConfig,
            warmupExerciseNames: seeded.warmupNames,
            applePlanID: row.id.planID,
            appleDateComponents: row.dateComponents,
            libraryWorkoutID: linkedID,
            libraryWorkoutTitle: linkedTitle,
            stepSections: stepSections.isEmpty ? Self.demoStepSections(title: row.title) : stepSections,
            readinessStore: readinessStore,
            prefsPersister: WatchItemPrefsAPIPersister()
        )
    }

    static func garmin(
        item: GarminQueueItem,
        readinessStore: any WatchItemReadinessStoring = WatchItemReadinessStore.shared,
        prefs: WorkoutPreferences? = nil,
        stepSections: [PreviewSection] = []
    ) -> WatchItemViewModel {
        let seeded = Self.seed(
            storeKey: item.workoutID,
            title: item.title,
            isApple: false,
            prefs: prefs,
            readinessStore: readinessStore
        )
        return WatchItemViewModel(
            device: .garmin,
            workoutID: item.workoutID,
            title: item.title,
            stateLine: item.statusLine,
            snapshotPills: seeded.pills,
            baseline: seeded.baseline,
            config: seeded.baselineConfig,
            draft: seeded.draft,
            draftConfig: seeded.draftConfig,
            warmupExerciseNames: seeded.warmupNames,
            garminState: item.state,
            libraryWorkoutID: item.workoutID,
            libraryWorkoutTitle: item.title,
            stepSections: stepSections.isEmpty ? Self.demoStepSections(title: item.title) : stepSections,
            readinessStore: readinessStore,
            prefsPersister: WatchItemPrefsAPIPersister()
        )
    }

    private struct Seed {
        var baseline: WatchItemReadinessState
        var baselineConfig: WatchItemConfigState
        var draft: WatchItemReadinessState
        var draftConfig: WatchItemConfigState
        var pills: [String]
        var warmupNames: [String]
    }

    private static func seed(
        storeKey: String,
        title: String,
        isApple: Bool,
        prefs: WorkoutPreferences?,
        readinessStore: any WatchItemReadinessStoring
    ) -> Seed {
        let fromPrefs = prefs.map { Self.config(from: $0) }
        let fallbackConfig = fromPrefs ?? Self.demoConfig(isApple: isApple, title: title)
        let fallbackReadiness = prefs.map { Self.readiness(from: $0) }
            ?? WatchItemReadinessState(
                mobilityEnabled: isApple,
                warmupsEnabled: isApple,
                restEnabled: true,
                cooldownEnabled: false
            )
        let delivered = readinessStore.loadDelivered(workoutID: storeKey)
        let draftSnap = readinessStore.loadDraft(workoutID: storeKey)

        let baseline = delivered?.readiness ?? fallbackReadiness
        let baselineConfig = delivered?.config ?? fallbackConfig
        let draft = draftSnap?.readiness ?? fallbackReadiness
        let draftConfig = draftSnap?.config ?? fallbackConfig
        let pills = delivered?.snapshotPills
            ?? Self.demoPills(isApple: isApple, title: title)
        let warmupNames = draftConfig.perExerciseRamps.map(\.exerciseRef)
        let names = warmupNames.isEmpty ? Self.demoWarmupNames(for: title) : warmupNames

        // First open: stamp delivered so baseline is stable across dismiss.
        if delivered == nil {
            readinessStore.saveDelivered(
                workoutID: storeKey,
                snapshot: WatchItemReadinessSnapshot(
                    readiness: baseline,
                    config: baselineConfig,
                    snapshotPills: pills,
                    updatedAt: Date()
                )
            )
        }
        if draftSnap == nil {
            readinessStore.saveDraft(
                workoutID: storeKey,
                snapshot: WatchItemReadinessSnapshot(
                    readiness: draft,
                    config: draftConfig,
                    snapshotPills: pills,
                    updatedAt: Date()
                )
            )
        }

        return Seed(
            baseline: baseline,
            baselineConfig: baselineConfig,
            draft: draft,
            draftConfig: draftConfig,
            pills: pills,
            warmupNames: names
        )
    }

    private static func readiness(from prefs: WorkoutPreferences) -> WatchItemReadinessState {
        WatchItemReadinessState(
            mobilityEnabled: prefs.sessionWarmup.enabled,
            warmupsEnabled: prefs.exerciseWarmupSets.enabled,
            restEnabled: prefs.betweenSetRest.enabled,
            cooldownEnabled: prefs.cooldown.enabled
        )
    }

    private static func config(from prefs: WorkoutPreferences) -> WatchItemConfigState {
        WatchItemConfigState(
            mobilityActivities: prefs.sessionWarmup.activities,
            cooldownActivities: prefs.cooldown.activities.isEmpty
                ? WorkoutEnrichmentMutations.defaultCooldownActivities()
                : prefs.cooldown.activities,
            perExerciseRamps: prefs.exerciseWarmupSets.perExercise ?? [],
            restOpen: prefs.betweenSetRest.restOpen,
            restSec: WorkoutEnrichmentPushCopy.normalizedRestSec(prefs.betweenSetRest.restSec ?? 60)
        )
    }

    private static func appleStateLine(for row: WorkoutScheduleRow, calendar: Calendar) -> String {
        guard let date = row.scheduledAt else {
            return "SCHEDULED · UNSCHEDULED · WORKOUT APP"
        }
        let day: String
        if calendar.isDateInToday(date) {
            day = "TODAY"
        } else if calendar.isDateInTomorrow(date) {
            day = "TOMORROW"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            day = formatter.string(from: date).uppercased()
        }
        let time = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        return "SCHEDULED · \(day) · \(time) · WORKOUT APP"
    }

    private static func demoPills(isApple: Bool, title: String) -> [String] {
        let isEMOM = title.uppercased().contains("EMOM")
        if isApple {
            return ["9 STEPS", "MOBILITY ×2", "RAMPS ×1", "OPEN REST"]
        }
        if isEMOM {
            return ["4 STEPS", "EMOM 10 MIN", "NO PREP", "LAP REST"]
        }
        return ["6 STEPS", "MOBILITY ×1", "NO RAMPS", "OPEN REST"]
    }

    private static func pills(
        from readiness: WatchItemReadinessState,
        config: WatchItemConfigState,
        isApple: Bool,
        title: String
    ) -> [String] {
        var pills: [String] = []
        var steps = 0
        if readiness.mobilityEnabled {
            let n = max(config.mobilityActivities.count, 1)
            steps += n
            pills.append("MOBILITY ×\(n)")
        }
        if readiness.warmupsEnabled {
            let n = config.perExerciseRamps.filter(\.enabled).count
            if n > 0 {
                steps += n * 3
                pills.append("RAMPS ×\(n)")
            } else if title.uppercased().contains("EMOM"), !isApple {
                pills.append("NO PREP")
            }
        }
        if readiness.restEnabled {
            pills.append(config.restOpen ? "OPEN REST" : "TIMED REST")
            steps += 1
        }
        if readiness.cooldownEnabled {
            let n = max(config.cooldownActivities.count, 1)
            steps += n
            pills.append("COOLDOWN ×\(n)")
        }
        pills.insert("\(max(steps, 1)) STEPS", at: 0)
        return pills
    }

    private static func demoWarmupNames(for title: String) -> [String] {
        if title.uppercased().contains("EMOM") {
            return ["Power Clean", "Push Press"]
        }
        return ["Bench Press", "Back Squat", "Romanian Deadlift"]
    }

    private static func demoConfig(isApple: Bool, title: String) -> WatchItemConfigState {
        let mobility: [EnrichmentActivityPref] = [
            EnrichmentActivityPref(
                name: "Ski erg",
                goal: try? ActivityGoal(kind: .distance, value: 500)
            ),
            EnrichmentActivityPref(
                name: "Jump rope",
                durationSec: 120,
                goal: try? ActivityGoal(kind: .time, value: 120)
            )
        ]
        let cooldown = WorkoutEnrichmentMutations.defaultCooldownActivities()
        let names = demoWarmupNames(for: title)
        let ramps: [PerExerciseRamp] = names.prefix(1).map { name in
            PerExerciseRamp(
                exerciseRef: name,
                enabled: true,
                sets: WorkoutEnrichmentMutations.defaultRampSets()
            )
        }
        return WatchItemConfigState(
            mobilityActivities: mobility,
            cooldownActivities: cooldown,
            perExerciseRamps: ramps,
            restOpen: true,
            restSec: 60
        )
    }

    private static func demoStepSections(title: String) -> [PreviewSection] {
        [
            PreviewSection(
                accent: .mobility,
                band: "MOBILITY",
                tag: nil,
                steps: [
                    PreviewStep(number: 1, title: "Ski erg", detail: "500 m", restChip: nil),
                    PreviewStep(number: 2, title: "Jump rope", detail: "2:00", restChip: nil)
                ]
            ),
            PreviewSection(
                accent: .work,
                band: "WARM-UP · \(demoWarmupNames(for: title).first ?? "BENCH")",
                tag: nil,
                steps: [
                    PreviewStep(number: 3, title: "8 × ~40%", detail: "easy", restChip: nil),
                    PreviewStep(number: 4, title: "5 × ~60%", detail: nil, restChip: nil),
                    PreviewStep(number: 5, title: "3 × ~80%", detail: nil, restChip: nil)
                ]
            ),
            PreviewSection(
                accent: .work,
                band: "WORK",
                tag: nil,
                steps: demoWarmupNames(for: title).enumerated().map { idx, name in
                    PreviewStep(number: 6 + idx, title: name, detail: "3 × 5", restChip: nil)
                }
            )
        ]
    }

    func summary(for row: WatchItemReadinessRow) -> String {
        let isEnabled = tracker.draft.isEnabled(row)
        guard isEnabled else { return "OFF" }
        switch row {
        case .mobility:
            return WorkoutEnrichmentPushCopy.sequenceSummary(
                mobilityActivities.map(EnrichmentActivity.init(pref:))
            )
        case .warmups:
            if !isApple, title.uppercased().contains("EMOM") {
                return WatchItemCopy.garminWarmupsUnused
            }
            if perExerciseRamps.isEmpty {
                return "NO EXERCISES"
            }
            let pairs: [(name: String, ramp: PerExerciseRamp?)] = warmupExerciseNames.map { name in
                let key = ExerciseKeyNormalizer.normalize(name)
                let ramp = perExerciseRamps.first {
                    ExerciseKeyNormalizer.normalize($0.exerciseRef) == key
                }
                return (name: name, ramp: ramp)
            }
            return WorkoutEnrichmentPushCopy.warmupSetsSummaryV2(pairs)
        case .rest:
            if !isApple, title.uppercased().contains("EMOM") {
                return WatchItemCopy.garminRestLap
            }
            return WorkoutEnrichmentPushCopy.liveRestDetail(
                restOpen: restOpen,
                restSec: restSec,
                target: enrichmentTarget
            )
        case .cooldown:
            return WorkoutEnrichmentPushCopy.sequenceSummary(
                cooldownActivities.map(EnrichmentActivity.init(pref:)),
                suffix: WorkoutEnrichmentPushCopy.cooldownRowSummarySuffix
            )
        }
    }
}

// MARK: - Prefs bridge (shared with pre-send sheet)

protocol WatchItemPrefsPersisting: Sendable {
    func persist(snapshot: WatchItemReadinessSnapshot)
}

/// Best-effort PUT of standing workout preferences so enhance sheet seeds match.
struct WatchItemPrefsAPIPersister: WatchItemPrefsPersisting {
    func persist(snapshot: WatchItemReadinessSnapshot) {
        Task {
            let api = AppDependencies.current.apiService
            guard var prefs = try? await api.fetchWorkoutPreferences() else { return }
            prefs.sessionWarmup.enabled = snapshot.readiness.mobilityEnabled
            prefs.sessionWarmup.activities = snapshot.config.mobilityActivities
            prefs.exerciseWarmupSets.enabled = snapshot.readiness.warmupsEnabled
            prefs.exerciseWarmupSets.perExercise = snapshot.config.perExerciseRamps
            prefs.betweenSetRest.enabled = snapshot.readiness.restEnabled
            try? prefs.betweenSetRest.setRest(
                restSec: snapshot.config.restOpen ? nil : snapshot.config.restSec,
                restOpen: snapshot.config.restOpen
            )
            prefs.cooldown.enabled = snapshot.readiness.cooldownEnabled
            prefs.cooldown.activities = snapshot.config.cooldownActivities
            _ = try? await api.updateWorkoutPreferences(prefs)
        }
    }
}
