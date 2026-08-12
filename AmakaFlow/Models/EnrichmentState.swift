//
//  EnrichmentState.swift
//  AmakaFlow
//
//  AMA-2408 F3/F4 — pure enrichment decision state. `seed` is the ONLY
//  load-order home: this workout's saved prefs → global defaults only if none.
//

import Foundation

/// Full enrichment decision the sheets render and the planner consumes.
struct EnrichmentState: Equatable, Sendable {
    var checkedKinds: Set<EnrichmentKind>
    var mobilityActivities: [EnrichmentActivityPref]
    var cooldownActivities: [EnrichmentActivityPref]
    var perExerciseRamps: [PerExerciseRamp]
    var restOpen: Bool
    var restSec: Int
    /// AMA-2423 — Transitions row config, parallel to `restOpen`/`restSec`.
    /// Only meaningful when `.stationTransition` is checked (XOR with Rest).
    /// Defaulted so the synthesized memberwise init stays source-compatible
    /// with call sites (e.g. `WatchItemViewModel`) that predate this kind.
    var transitionOpen: Bool = false
    var transitionSec: Int = 60
    /// Warm-up candidates from the current workout — never invents ramps for
    /// names that appear later (late-added exercises stay unchecked).
    var candidateExerciseNames: [String]
    var target: EnrichmentPushTarget

    /// Durable per-workout prefs (UserDefaults via `EnrichmentPrefsStore`).
    struct Persisted: Equatable, Codable, Sendable {
        var checkedKinds: [EnrichmentKind]
        var mobilityActivities: [EnrichmentActivityPref]
        var cooldownActivities: [EnrichmentActivityPref]
        var perExerciseRamps: [PerExerciseRamp]
        var restOpen: Bool
        var restSec: Int
        /// AMA-2423 — additive; absent in pre-existing saved payloads (decode
        /// falls back to `StationTransitionPrefs.defaults`-equivalent values).
        var transitionOpen: Bool
        var transitionSec: Int

        // Nested CodingKeys trips SwiftLint `nesting` at the default type_level.
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case checkedKinds = "checked_kinds"
            case mobilityActivities = "mobility_activities"
            case cooldownActivities = "cooldown_activities"
            case perExerciseRamps = "per_exercise_ramps"
            case restOpen = "rest_open"
            case restSec = "rest_sec"
            case transitionOpen = "transition_open"
            case transitionSec = "transition_sec"
        }

        var checkedKindSet: Set<EnrichmentKind> { Set(checkedKinds) }

        init(
            checkedKinds: [EnrichmentKind],
            mobilityActivities: [EnrichmentActivityPref],
            cooldownActivities: [EnrichmentActivityPref],
            perExerciseRamps: [PerExerciseRamp],
            restOpen: Bool,
            restSec: Int,
            transitionOpen: Bool = false,
            transitionSec: Int = 60
        ) {
            self.checkedKinds = checkedKinds
            self.mobilityActivities = mobilityActivities
            self.cooldownActivities = cooldownActivities
            self.perExerciseRamps = perExerciseRamps
            self.restOpen = restOpen
            self.restSec = restSec
            self.transitionOpen = transitionOpen
            self.transitionSec = transitionSec
        }

        /// Lenient `checked_kinds`: unknown raw values drop that entry only so a
        /// newer build's kind cannot wipe the whole workout preference payload.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawKinds = try container.decode([String].self, forKey: .checkedKinds)
            checkedKinds = rawKinds.compactMap(EnrichmentKind.init(rawValue:))
            mobilityActivities = try container.decode(
                [EnrichmentActivityPref].self,
                forKey: .mobilityActivities
            )
            cooldownActivities = try container.decode(
                [EnrichmentActivityPref].self,
                forKey: .cooldownActivities
            )
            perExerciseRamps = try container.decode(
                [PerExerciseRamp].self,
                forKey: .perExerciseRamps
            )
            restOpen = try container.decode(Bool.self, forKey: .restOpen)
            restSec = try container.decode(Int.self, forKey: .restSec)
            // AMA-2423 — legacy saves predate these keys; default off/nil-equivalent.
            transitionOpen = try container.decodeIfPresent(Bool.self, forKey: .transitionOpen) ?? false
            transitionSec = try container.decodeIfPresent(Int.self, forKey: .transitionSec) ?? 60
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(checkedKinds.map(\.rawValue), forKey: .checkedKinds)
            try container.encode(mobilityActivities, forKey: .mobilityActivities)
            try container.encode(cooldownActivities, forKey: .cooldownActivities)
            try container.encode(perExerciseRamps, forKey: .perExerciseRamps)
            try container.encode(restOpen, forKey: .restOpen)
            try container.encode(restSec, forKey: .restSec)
            try container.encode(transitionOpen, forKey: .transitionOpen)
            try container.encode(transitionSec, forKey: .transitionSec)
        }
    }

    // MARK: - Seed (ONLY load-order home)

    /// Load order: **this workout's saved prefs → global defaults only if none**.
    static func seed(
        workoutPrefs: Persisted?,
        globalDefaults: WorkoutPreferences,
        defaultCheckedKinds: Set<EnrichmentKind>,
        candidateExerciseNames: [String],
        target: EnrichmentPushTarget
    ) -> EnrichmentState {
        if let saved = workoutPrefs {
            return EnrichmentState(
                checkedKinds: saved.checkedKindSet,
                mobilityActivities: saved.mobilityActivities,
                // Saved prefs win verbatim — empty cool-down is an explicit pick.
                cooldownActivities: saved.cooldownActivities,
                // Late-added exercises: absent from perExerciseRamps → unchecked.
                perExerciseRamps: saved.perExerciseRamps,
                restOpen: saved.restOpen,
                restSec: WorkoutEnrichmentPushCopy.normalizedRestSec(saved.restSec),
                transitionOpen: saved.transitionOpen,
                transitionSec: WorkoutEnrichmentPushCopy.normalizedTransitionSec(saved.transitionSec),
                candidateExerciseNames: candidateExerciseNames,
                target: target
            )
        }

        let cooldown = globalDefaults.cooldown.activities.isEmpty
            ? WorkoutEnrichmentMutations.defaultCooldownActivities()
            : globalDefaults.cooldown.activities
        return EnrichmentState(
            checkedKinds: defaultCheckedKinds,
            mobilityActivities: globalDefaults.sessionWarmup.activities,
            cooldownActivities: cooldown,
            // Globals seed ramps ONLY when the standing prefs already carry
            // explicit per-exercise entries — never invent from default_sets.
            perExerciseRamps: globalDefaults.exerciseWarmupSets.perExercise ?? [],
            restOpen: WorkoutEnrichmentPushCopy.initialRestOpen(
                standing: globalDefaults.betweenSetRest,
                target: target
            ),
            restSec: WorkoutEnrichmentPushCopy.normalizedRestSec(
                globalDefaults.betweenSetRest.restSec
            ),
            transitionOpen: WorkoutEnrichmentPushCopy.initialTransitionOpen(
                standing: globalDefaults.stationTransition,
                target: target
            ),
            transitionSec: WorkoutEnrichmentPushCopy.normalizedTransitionSec(
                globalDefaults.stationTransition.transitionSec
            ),
            candidateExerciseNames: candidateExerciseNames,
            target: target
        )
    }

    /// Convenience: seed from a push plan + standing globals + optional save.
    /// Saved checked kinds are intersected with `plan.offers` so a stale kind
    /// cannot enable application for an offer the plan does not present.
    static func seed(
        workoutPrefs: Persisted?,
        globalDefaults: WorkoutPreferences,
        plan: WorkoutEnrichmentPushPlanner.Plan
    ) -> EnrichmentState {
        let offeredKinds = Set(plan.offers.map(\.kind))
        let filteredPrefs = workoutPrefs.map { saved -> Persisted in
            var next = saved
            next.checkedKinds = saved.checkedKinds.filter { offeredKinds.contains($0) }
            return next
        }
        return seed(
            workoutPrefs: filteredPrefs,
            globalDefaults: globalDefaults,
            defaultCheckedKinds: plan.defaultCheckedKinds,
            candidateExerciseNames: plan.offer(.exerciseWarmupSets)?.candidateExerciseNames ?? [],
            target: plan.target
        )
    }

    // MARK: - Persist / decision

    func persisted() -> Persisted {
        Persisted(
            checkedKinds: Array(checkedKinds).sorted { $0.rawValue < $1.rawValue },
            mobilityActivities: mobilityActivities,
            cooldownActivities: cooldownActivities,
            perExerciseRamps: perExerciseRamps,
            restOpen: restOpen,
            restSec: restSec,
            transitionOpen: transitionOpen,
            transitionSec: transitionSec
        )
    }

    /// Planner input — door edits only ride along when their kind is checked.
    var decision: WorkoutEnrichmentPushPlanner.Decision {
        WorkoutEnrichmentPushPlanner.Decision(
            checkedKinds: checkedKinds,
            restSecOverride: checkedKinds.contains(.betweenSetRest) && !restOpen ? restSec : nil,
            restOpenOverride: checkedKinds.contains(.betweenSetRest) ? restOpen : nil,
            sessionWarmupActivities: checkedKinds.contains(.sessionWarmup) ? mobilityActivities : nil,
            cooldownActivities: checkedKinds.contains(.cooldown) ? cooldownActivities : nil,
            // Empty array is intentional (opt-in): tells apply to exclude all.
            perExerciseRamps: checkedKinds.contains(.exerciseWarmupSets) ? perExerciseRamps : nil,
            transitionSecOverride: checkedKinds.contains(.stationTransition) && !transitionOpen ? transitionSec : nil,
            transitionOpenOverride: checkedKinds.contains(.stationTransition) ? transitionOpen : nil
        )
    }

    // MARK: - Summaries (delegate to EnrichmentRowSummary)

    func summary(for kind: EnrichmentKind) -> String? {
        switch kind {
        case .exerciseWarmupSets:
            return EnrichmentRowSummary.warmups(
                isOn: checkedKinds.contains(.exerciseWarmupSets),
                candidateNames: candidateExerciseNames,
                ramps: perExerciseRamps
            )
        case .sessionWarmup:
            return EnrichmentRowSummary.sequence(
                isOn: checkedKinds.contains(.sessionWarmup),
                activities: mobilityActivities.map(EnrichmentActivity.init(pref:))
            )
        case .cooldown:
            return EnrichmentRowSummary.sequence(
                isOn: checkedKinds.contains(.cooldown),
                activities: cooldownActivities.map(EnrichmentActivity.init(pref:))
            )
        case .betweenSetRest:
            return EnrichmentRowSummary.rest(
                isOn: checkedKinds.contains(.betweenSetRest),
                restOpen: restOpen,
                restSec: restSec,
                target: target
            )
        case .stationTransition:
            return EnrichmentRowSummary.transition(
                isOn: checkedKinds.contains(.stationTransition),
                transitionOpen: transitionOpen,
                transitionSec: transitionSec,
                target: target
            )
        }
    }

    func summary(for row: WatchItemReadinessRow) -> String? {
        switch row {
        case .mobility: return summary(for: EnrichmentKind.sessionWarmup)
        case .warmups: return summary(for: EnrichmentKind.exerciseWarmupSets)
        case .rest: return summary(for: EnrichmentKind.betweenSetRest)
        case .transition: return summary(for: EnrichmentKind.stationTransition)
        case .cooldown: return summary(for: EnrichmentKind.cooldown)
        }
    }

    /// True when warm-ups are ON with zero opted-in ramps (amber CTA).
    var needsWarmupPick: Bool {
        checkedKinds.contains(.exerciseWarmupSets)
            && EnrichmentRowSummary.enabledRamps(
                in: perExerciseRamps,
                candidates: candidateExerciseNames
            ).isEmpty
    }
}

extension EnrichmentState.Persisted {
    /// Bridge Watch Item draft/delivered config into the shared persisted shape.
    static func from(
        readiness: WatchItemReadinessState,
        config: WatchItemConfigState
    ) -> EnrichmentState.Persisted {
        var kinds: [EnrichmentKind] = []
        if readiness.mobilityEnabled { kinds.append(.sessionWarmup) }
        if readiness.warmupsEnabled { kinds.append(.exerciseWarmupSets) }
        if readiness.restEnabled { kinds.append(.betweenSetRest) }
        // AMA-2423 — Transitions must survive the round-trip. Dropping it here
        // let a Watch Item toggle silently reset the workout's saved
        // Transitions config to the defaults (open off / 60s).
        if readiness.transitionEnabled { kinds.append(.stationTransition) }
        if readiness.cooldownEnabled { kinds.append(.cooldown) }
        return EnrichmentState.Persisted(
            checkedKinds: kinds,
            mobilityActivities: config.mobilityActivities,
            cooldownActivities: config.cooldownActivities,
            perExerciseRamps: config.perExerciseRamps,
            restOpen: config.restOpen,
            restSec: config.restSec,
            transitionOpen: config.transitionOpen,
            transitionSec: config.transitionSec
        )
    }

    func asReadiness() -> WatchItemReadinessState {
        WatchItemReadinessState(
            mobilityEnabled: checkedKindSet.contains(.sessionWarmup),
            warmupsEnabled: checkedKindSet.contains(.exerciseWarmupSets),
            restEnabled: checkedKindSet.contains(.betweenSetRest),
            cooldownEnabled: checkedKindSet.contains(.cooldown),
            transitionEnabled: checkedKindSet.contains(.stationTransition)
        )
    }

    func asConfig() -> WatchItemConfigState {
        WatchItemConfigState(
            mobilityActivities: mobilityActivities,
            cooldownActivities: cooldownActivities,
            perExerciseRamps: perExerciseRamps,
            restOpen: restOpen,
            restSec: restSec,
            transitionOpen: transitionOpen,
            transitionSec: transitionSec
        )
    }
}
