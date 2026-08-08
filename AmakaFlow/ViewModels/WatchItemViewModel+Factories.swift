//
//  WatchItemViewModel+Factories.swift
//  AmakaFlow
//
//  AMA-2388: Apple/Garmin factories, store seed, and pill derivation.
//  AMA-2390: production never falls back to demo steps/pills; draft without a
//  store snapshot mirrors the delivered baseline (no ghost EDITED).
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
        // Capture plan JSON before resolve — stale Library links drop the binding
        // and must not erase the cached payload needed for Watch Item sections.
        let cachedPlanJSON = linkStore.planJSON(forPlanID: planKey)
        let linkedID = linkStore.resolve(planID: planKey, title: row.title, library: library)
        if let linkedID {
            readinessStore.migrate(from: planKey, to: linkedID)
        }
        let linkedTitle = linkedID.flatMap { id in library.first { $0.id == id }?.title }
            ?? (linkedID != nil ? row.title : nil)
        let storeKey = linkedID ?? planKey
        let sections = resolvedStepSections(
            stepSections: stepSections,
            planJSON: cachedPlanJSON ?? linkStore.planJSON(forPlanID: planKey),
            title: row.title
        )
        let seeded = seed(
            storeKey: storeKey,
            title: row.title,
            isApple: true,
            prefs: prefs,
            readinessStore: readinessStore,
            deliveredStepTotal: sections.reduce(0) { $0 + $1.steps.count },
            stepSections: sections
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
        let sections = resolvedStepSections(
            stepSections: stepSections,
            planJSON: nil,
            title: item.title
        )
        let seeded = seed(
            storeKey: item.workoutID,
            title: item.title,
            isApple: false,
            prefs: prefs,
            readinessStore: readinessStore,
            deliveredStepTotal: sections.reduce(0) { $0 + $1.steps.count },
            stepSections: sections
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

    /// Prefer caller sections, else cached planJSON, else demo only when dogfood flag is on.
    static func resolvedStepSections(
        stepSections: [PreviewSection],
        planJSON: Data?,
        title: String
    ) -> [PreviewSection] {
        if !stepSections.isEmpty { return stepSections }
        if let planJSON, !planJSON.isEmpty {
            let fromPlan = WorkoutKitPlanStepSummary.sections(from: planJSON)
            if !fromPlan.isEmpty { return fromPlan }
        }
        guard OnYourWatchesDemoSupport.isEnabled else { return [] }
        return demoStepSections(title: title)
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
        deliveredStepTotal: Int? = nil,
        stepSections: [PreviewSection] = []
    ) -> Seed {
        let useDemo = OnYourWatchesDemoSupport.isEnabled
        let fromPrefsConfig = prefs.map { config(from: $0) }
        let fromPrefsReadiness = prefs.map { readiness(from: $0) }
        let defaultsConfig = config(from: .defaults)
        let defaultsReadiness = readiness(from: .defaults)

        let fallbackConfig = fromPrefsConfig
            ?? (useDemo ? demoConfig(isApple: isApple, title: title) : defaultsConfig)
        let fallbackReadiness = fromPrefsReadiness
            ?? (useDemo
                ? WatchItemReadinessState(
                    mobilityEnabled: isApple,
                    warmupsEnabled: isApple,
                    restEnabled: true,
                    cooldownEnabled: false
                )
                : defaultsReadiness)

        var delivered = readinessStore.loadDelivered(workoutID: storeKey)
        var draftSnap = readinessStore.loadDraft(workoutID: storeKey)

        // Production: discard delivered snapshots stamped by prior demo behavior.
        var replacedStaleDemoDelivered = false
        if !useDemo, let snap = delivered, isStaleDemoSnapshot(snap, title: title, isApple: isApple) {
            delivered = nil
            replacedStaleDemoDelivered = true
        }

        let baseline = delivered?.readiness ?? fallbackReadiness
        let baselineConfig = delivered?.config ?? fallbackConfig

        // Stale demo draft vs authentic baseline → ghost EDITED. Drop it.
        if let snap = draftSnap, isStaleDemoSnapshot(snap, title: title, isApple: isApple) {
            let baselineIsAuthentic = delivered != nil || prefs != nil || !useDemo
            if baselineIsAuthentic, snap.config != baselineConfig || snap.readiness != baseline {
                draftSnap = nil
            }
        }

        // No draft snapshot → mirror delivered/fallback baseline (never a divergent demo).
        let draft = draftSnap?.readiness ?? baseline
        let draftConfig = draftSnap?.config ?? baselineConfig

        let pills: [String]
        if let deliveredPills = delivered?.snapshotPills, !deliveredPills.isEmpty {
            pills = deliveredPills
        } else if prefs != nil || delivered != nil || !useDemo {
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

        let rampNames = draftConfig.perExerciseRamps.map(\.exerciseRef)
        let names: [String]
        if !rampNames.isEmpty {
            names = rampNames
        } else {
            let fromSections = workExerciseNames(from: stepSections)
            if !fromSections.isEmpty {
                names = fromSections
            } else if useDemo {
                names = demoWarmupNames(for: title)
            } else {
                names = []
            }
        }

        // Persist authentic baselines — replace stale demo delivered, or seed from prefs.
        if replacedStaleDemoDelivered || (delivered == nil && prefs != nil) {
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
        if draftSnap == nil, prefs != nil || replacedStaleDemoDelivered {
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

    /// Demo config used only as a dogfood placeholder — never a real edit.
    static func isStaleDemoSnapshot(
        _ snap: WatchItemReadinessSnapshot,
        title: String,
        isApple: Bool
    ) -> Bool {
        snap.config == demoConfig(isApple: isApple, title: title)
    }

    /// Backward-compatible alias for draft-only call sites / tests.
    static func isStaleDemoDraft(
        _ snap: WatchItemReadinessSnapshot,
        title: String,
        isApple: Bool
    ) -> Bool {
        isStaleDemoSnapshot(snap, title: title, isApple: isApple)
    }

    /// Work-band exercise names for ramp pickers (Circuit stations or band titles).
    static func workExerciseNames(from sections: [PreviewSection]) -> [String] {
        sections
            .filter { $0.accent == .work && !$0.band.uppercased().contains("WARM") }
            .flatMap { section -> [String] in
                if section.band.caseInsensitiveCompare("Circuit") == .orderedSame {
                    return section.steps.map(\.title)
                }
                return [section.band]
            }
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

        func appendNumbered(_ title: String, detail: String? = nil, restChip: String? = nil) -> PreviewStep {
            let step = PreviewStep(
                number: nextNumber,
                title: title,
                detail: detail,
                restChip: restChip
            )
            nextNumber += 1
            return step
        }

        if readiness.mobilityEnabled {
            let names = config.mobilityActivities.map(\.name)
            let labels = names.isEmpty ? ["Mobility"] : names
            sections.append(
                PreviewSection(
                    accent: .mobility,
                    band: "MOBILITY",
                    tag: nil,
                    steps: labels.map { appendNumbered($0) }
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
                        steps: details.map { appendNumbered(PreviewStep.warmupSetTitle, detail: $0) }
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
                    steps: band.steps.map {
                        appendNumbered($0.title, detail: $0.detail, restChip: $0.restChip)
                    },
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
                    steps: labels.map { appendNumbered($0) }
                )
            )
        }

        return sections.isEmpty ? priorSections : sections
    }
}
