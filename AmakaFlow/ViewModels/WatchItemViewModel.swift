//
//  WatchItemViewModel.swift
//  AmakaFlow
//
//  AMA-2386: sheet state — readiness draft, AMA-2378 configurators, replace + toast.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class WatchItemViewModel: ObservableObject {
    let device: WatchItemDevice
    let workoutID: String
    let title: String
    let stateLine: String
    let snapshotPills: [String]
    let applePlanID: String?
    let appleDateComponents: DateComponents?
    let garminState: GarminQueueItemState?
    /// Warm-up pick candidates (demo names until live workout blocks are wired).
    let warmupExerciseNames: [String]

    @Published private(set) var tracker: WatchItemChangeTracker
    @Published private(set) var isReplacing = false
    @Published var lastError: String?

    private let replacer: any WatchItemReplacing
    private let toast: DDToastCenter

    var isApple: Bool { device.isApple }
    var changeCount: Int { tracker.changeCount }
    var hasChanges: Bool { tracker.hasChanges }

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
        warmupExerciseNames: [String] = [],
        applePlanID: String? = nil,
        appleDateComponents: DateComponents? = nil,
        garminState: GarminQueueItemState? = nil,
        replacer: (any WatchItemReplacing)? = nil,
        toast: DDToastCenter? = nil
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
        self.tracker = WatchItemChangeTracker(baseline: baseline, config: config)
        self.replacer = replacer ?? WatchItemReplaceCoordinator()
        self.toast = toast ?? DDToastCenter.shared
    }

    func setEnabled(_ row: WatchItemReadinessRow, _ enabled: Bool) {
        guard !isReplacing else { return }
        var next = tracker
        next.setEnabled(row, enabled)
        tracker = next
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
        return WatchItemCopy.replaceCTA(changeCount: changeCount)
    }

    var canReplace: Bool { hasChanges && !isReplacing }

    func replace() async {
        guard canReplace else { return }
        isReplacing = true
        lastError = nil
        let toastId = toast.beginPending(text: WatchItemCopy.toastPending)

        let request = WatchItemReplaceRequest(
            device: device,
            workoutID: workoutID,
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
            toast.resolve(
                id: toastId,
                kind: .device,
                text: WatchItemCopy.toastSuccess(isApple: isApple)
            )
        case .failure(let error):
            let message = error.errorDescription ?? "Replace failed"
            lastError = message
            toast.resolve(id: toastId, kind: .error, text: message)
        }
        isReplacing = false
    }

    // MARK: - Factories

    static func apple(row: WorkoutScheduleRow, calendar: Calendar = .current) -> WatchItemViewModel {
        let when = Self.appleStateLine(for: row, calendar: calendar)
        return WatchItemViewModel(
            device: .apple,
            workoutID: row.id.planID,
            title: row.title,
            stateLine: when,
            snapshotPills: Self.demoPills(isApple: true, title: row.title),
            baseline: WatchItemReadinessState(
                mobilityEnabled: true,
                warmupsEnabled: true,
                restEnabled: true,
                cooldownEnabled: false
            ),
            config: Self.demoConfig(isApple: true, title: row.title),
            warmupExerciseNames: Self.demoWarmupNames(for: row.title),
            applePlanID: row.id.planID,
            appleDateComponents: row.dateComponents
        )
    }

    static func garmin(item: GarminQueueItem) -> WatchItemViewModel {
        WatchItemViewModel(
            device: .garmin,
            workoutID: item.workoutID,
            title: item.title,
            stateLine: item.statusLine,
            snapshotPills: Self.demoPills(isApple: false, title: item.title),
            baseline: WatchItemReadinessState(
                mobilityEnabled: false,
                warmupsEnabled: false,
                restEnabled: true,
                cooldownEnabled: false
            ),
            config: Self.demoConfig(isApple: false, title: item.title),
            warmupExerciseNames: Self.demoWarmupNames(for: item.title),
            garminState: item.state
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

    func summary(for row: WatchItemReadinessRow) -> String {
        let on = tracker.draft.isEnabled(row)
        guard on else { return "OFF" }
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
