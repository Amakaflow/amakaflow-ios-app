//
//  WatchItemViewModel+Factories.swift
//  AmakaFlow
//
//  AMA-2388: Apple/Garmin factories, store seed, and pill derivation.
//

import Foundation

@MainActor
extension WatchItemViewModel {
    struct Seed {
        var baseline: WatchItemReadinessState
        var baselineConfig: WatchItemConfigState
        var draft: WatchItemReadinessState
        var draftConfig: WatchItemConfigState
        var pills: [String]
        var warmupNames: [String]
    }

    static func apple(
        row: WorkoutScheduleRow,
        calendar: Calendar = .current,
        linkStore: any AppleScheduledWorkoutLinkStoring = AppleScheduledWorkoutLinkStore.shared,
        readinessStore: any WatchItemReadinessStoring = WatchItemReadinessStore.shared,
        library: [(id: String, title: String)] = [],
        prefs: WorkoutPreferences? = nil,
        stepSections: [PreviewSection] = []
    ) -> WatchItemViewModel {
        let when = appleStateLine(for: row, calendar: calendar)
        let planKey = row.id.planID
        let linkedID = linkStore.resolve(planID: planKey, title: row.title, library: library)
        if let linkedID {
            readinessStore.migrate(from: planKey, to: linkedID)
        }
        let linkedTitle = linkedID.flatMap { id in library.first { $0.id == id }?.title }
            ?? (linkedID != nil ? row.title : nil)
        let storeKey = linkedID ?? planKey
        let sections = stepSections.isEmpty ? demoStepSections(title: row.title) : stepSections
        let seeded = seed(
            storeKey: storeKey,
            title: row.title,
            isApple: true,
            prefs: prefs,
            readinessStore: readinessStore,
            deliveredStepTotal: sections.reduce(0) { $0 + $1.steps.count }
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
            applePlanID: planKey,
            appleDateComponents: row.dateComponents,
            libraryWorkoutID: linkedID,
            libraryWorkoutTitle: linkedTitle,
            stepSections: sections,
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
        let sections = stepSections.isEmpty ? demoStepSections(title: item.title) : stepSections
        let seeded = seed(
            storeKey: item.workoutID,
            title: item.title,
            isApple: false,
            prefs: prefs,
            readinessStore: readinessStore,
            deliveredStepTotal: sections.reduce(0) { $0 + $1.steps.count }
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
            stepSections: sections,
            readinessStore: readinessStore,
            prefsPersister: WatchItemPrefsAPIPersister()
        )
    }

    /// Seed in-memory state from store + prefs. Demo placeholders are display-only
    /// until real prefs or a Replace-delivered snapshot exists — never stamp demo
    /// as the durable delivered baseline.
    static func seed(
        storeKey: String,
        title: String,
        isApple: Bool,
        prefs: WorkoutPreferences?,
        readinessStore: any WatchItemReadinessStoring,
        deliveredStepTotal: Int? = nil
    ) -> Seed {
        let fromPrefs = prefs.map { config(from: $0) }
        let fallbackConfig = fromPrefs ?? demoConfig(isApple: isApple, title: title)
        let fallbackReadiness = prefs.map { readiness(from: $0) }
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
        let pills: [String]
        if let deliveredPills = delivered?.snapshotPills {
            pills = deliveredPills
        } else if prefs != nil {
            pills = Self.pills(
                from: baseline,
                config: baselineConfig,
                isApple: isApple,
                title: title,
                deliveredStepTotal: deliveredStepTotal
            )
        } else {
            pills = demoPills(isApple: isApple, title: title)
        }
        let warmupNames = draftConfig.perExerciseRamps.map(\.exerciseRef)
        let names = warmupNames.isEmpty ? demoWarmupNames(for: title) : warmupNames

        // Persist only authentic baselines (prefs or prior delivered) — never demo.
        if delivered == nil, prefs != nil {
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
        if draftSnap == nil, prefs != nil {
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

    static func readiness(from prefs: WorkoutPreferences) -> WatchItemReadinessState {
        WatchItemReadinessState(
            mobilityEnabled: prefs.sessionWarmup.enabled,
            warmupsEnabled: prefs.exerciseWarmupSets.enabled,
            restEnabled: prefs.betweenSetRest.enabled,
            cooldownEnabled: prefs.cooldown.enabled
        )
    }

    static func config(from prefs: WorkoutPreferences) -> WatchItemConfigState {
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

    static func appleStateLine(for row: WorkoutScheduleRow, calendar: Calendar) -> String {
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

    /// Build ON THE WATCH pills. `deliveredStepTotal` (full preview row count,
    /// including WORK) overrides the enrichment-only tally for the STEPS chip.
    static func pills(
        from readiness: WatchItemReadinessState,
        config: WatchItemConfigState,
        isApple: Bool,
        title: String,
        deliveredStepTotal: Int? = nil
    ) -> [String] {
        var pills: [String] = []
        var enrichmentSteps = 0
        if readiness.mobilityEnabled {
            let count = max(config.mobilityActivities.count, 1)
            enrichmentSteps += count
            pills.append("MOBILITY ×\(count)")
        }
        if readiness.warmupsEnabled {
            let enabledRamps = config.perExerciseRamps.filter(\.enabled)
            if !enabledRamps.isEmpty {
                let count = enabledRamps.count
                enrichmentSteps += count * 3
                pills.append("RAMPS ×\(count)")
            } else if title.uppercased().contains("EMOM"), !isApple {
                pills.append("NO PREP")
            }
        }
        if readiness.restEnabled {
            pills.append(config.restOpen ? "OPEN REST" : "TIMED REST")
            enrichmentSteps += 1
        }
        if readiness.cooldownEnabled {
            let count = max(config.cooldownActivities.count, 1)
            enrichmentSteps += count
            pills.append("COOLDOWN ×\(count)")
        }
        let total = deliveredStepTotal ?? max(enrichmentSteps, 1)
        pills.insert(WatchItemCopy.stepsPill(count: total), at: 0)
        return pills
    }

    /// Rebuild the read-only preview from the newly delivered draft while
    /// preserving prior WORK bands (exercise rows the enrichment draft doesn't own).
    static func sectionsReflectingDelivered(
        readiness: WatchItemReadinessState,
        config: WatchItemConfigState,
        priorSections: [PreviewSection]
    ) -> [PreviewSection] {
        var sections: [PreviewSection] = []
        var nextNumber = 1

        func numberedSteps(from titles: [(title: String, detail: String?)]) -> [PreviewStep] {
            titles.map { item in
                let step = PreviewStep(
                    number: nextNumber,
                    title: item.title,
                    detail: item.detail,
                    restChip: nil
                )
                nextNumber += 1
                return step
            }
        }

        if readiness.mobilityEnabled {
            let names = config.mobilityActivities.map(\.name)
            let labels = names.isEmpty ? ["Mobility"] : names
            sections.append(
                PreviewSection(
                    accent: .mobility,
                    band: "MOBILITY",
                    tag: nil,
                    steps: numberedSteps(from: labels.map { ($0, nil) })
                )
            )
        }

        if readiness.warmupsEnabled {
            let enabledRamps = config.perExerciseRamps.filter(\.enabled)
            for ramp in enabledRamps {
                let details = ["~40%", "~60%", "~80%"]
                sections.append(
                    PreviewSection(
                        accent: .work,
                        band: "WARM-UP · \(ramp.exerciseRef.uppercased())",
                        tag: nil,
                        steps: numberedSteps(from: details.map { (PreviewStep.warmupSetTitle, $0) })
                    )
                )
            }
        }

        let workBands = priorSections.filter {
            $0.accent == .work && !$0.band.uppercased().contains("WARM")
        }
        for band in workBands {
            sections.append(
                PreviewSection(
                    accent: .work,
                    band: band.band,
                    tag: band.tag,
                    steps: numberedSteps(from: band.steps.map { ($0.title, $0.detail) }),
                    caption: band.caption
                )
            )
        }

        if readiness.cooldownEnabled {
            let names = config.cooldownActivities.map(\.name)
            let labels = names.isEmpty ? ["Cooldown"] : names
            sections.append(
                PreviewSection(
                    accent: .cooldown,
                    band: "COOLDOWN",
                    tag: nil,
                    steps: numberedSteps(from: labels.map { ($0, nil) })
                )
            )
        }

        return sections.isEmpty ? priorSections : sections
    }
}
