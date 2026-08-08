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

    /// Prefer delivered preview row count (includes WORK); never parse pill copy.
    var stepCount: Int {
        let fromSections = stepSections.reduce(0) { $0 + $1.steps.count }
        if fromSections > 0 { return fromSections }
        return 1
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

    /// Avoid MainActor-isolated deinit + TaskLocal teardown crash under XCTest (Swift 6).
    nonisolated deinit {}

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
            // Rebuild delivered preview from the new draft so stepCount / overlay
            // match what was just pushed (not the pre-replace snapshot).
            stepSections = Self.sectionsReflectingDelivered(
                readiness: tracker.draft,
                config: tracker.draftConfig,
                priorSections: stepSections
            )
            snapshotPills = Self.pills(
                from: tracker.draft,
                config: tracker.draftConfig,
                isApple: isApple,
                title: title,
                deliveredStepTotal: stepCount
            )
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
