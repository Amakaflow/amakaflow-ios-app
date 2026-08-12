//
//  WorkoutEnrichmentPushPlanner+Application.swift
//  AmakaFlow
//
//  AMA-2378 — Decision / Application + apply helpers
//  (split from WorkoutEnrichmentPushPlanner.swift for SwiftLint type_body_length).
//

import Foundation

extension WorkoutEnrichmentPushPlanner {
    // MARK: - Apply

    /// What the user answered on the sheet.
    struct Decision: Equatable, Sendable {
        var checkedKinds: Set<EnrichmentKind>
        /// Rest override for this push. `nil` keeps the prefs value.
        var restSecOverride: Int?
        var restOpenOverride: Bool?
        /// AMA-2378 Task 6 — door-screen edits. `nil` keeps the standing prefs
        /// value (v1 equivalence); the sheet only fills these when the
        /// matching kind is checked (see `WorkoutEnrichmentPushSheet.decision`).
        var sessionWarmupActivities: [EnrichmentActivityPref]?
        var cooldownActivities: [EnrichmentActivityPref]?
        /// Full per-exercise ramp list the user configured in the warm-up
        /// pick/ramp editor screens — every candidate the user touched
        /// (enabled or disabled), not just the enabled ones.
        var perExerciseRamps: [PerExerciseRamp]?
        /// AMA-2423 — Transitions override for this push, parallel to
        /// `restSecOverride`/`restOpenOverride`. `nil` keeps the prefs value.
        var transitionSecOverride: Int?
        var transitionOpenOverride: Bool?

        init(
            checkedKinds: Set<EnrichmentKind>,
            restSecOverride: Int? = nil,
            restOpenOverride: Bool? = nil,
            sessionWarmupActivities: [EnrichmentActivityPref]? = nil,
            cooldownActivities: [EnrichmentActivityPref]? = nil,
            perExerciseRamps: [PerExerciseRamp]? = nil,
            transitionSecOverride: Int? = nil,
            transitionOpenOverride: Bool? = nil
        ) {
            self.checkedKinds = checkedKinds
            self.restSecOverride = restSecOverride
            self.restOpenOverride = restOpenOverride
            self.sessionWarmupActivities = sessionWarmupActivities
            self.cooldownActivities = cooldownActivities
            self.perExerciseRamps = perExerciseRamps
            self.transitionSecOverride = transitionSecOverride
            self.transitionOpenOverride = transitionOpenOverride
        }
    }

    /// Enrich inputs for the decision: unchecked kinds are disabled so enrich
    /// cannot inject them, rejected offers are tombstoned, and tombstones for
    /// checked re-opt-in kinds are dropped.
    struct Application: Equatable, Sendable {
        var prefs: WorkoutPreferences
        var tombstones: [EnrichmentTombstone]
        var clearedTombstones: [EnrichmentTombstone]
        var rejectedTombstones: [EnrichmentTombstone]

        var appliesAnything: Bool {
            prefs.sessionWarmup.enabled
                || prefs.cooldown.enabled
                || prefs.betweenSetRest.enabled
                || prefs.exerciseWarmupSets.enabled
                // AMA-2423 — Transitions-only accepts must still call mapper
                // enrich; without this a checked Transitions-only decision
                // would silently persist tombstones/prefs and never write
                // transition_open/transition_sec onto the block.
                || prefs.stationTransition.enabled
        }

        /// True when the sheet answer must be persisted (enrich and/or tombstones).
        var needsPersist: Bool {
            appliesAnything || !rejectedTombstones.isEmpty || !clearedTombstones.isEmpty
        }
    }

    static func application(
        plan: Plan,
        decision: Decision,
        prefs: WorkoutPreferences,
        tombstones: [EnrichmentTombstone]
    ) throws -> Application {
        var overridden = prefs
        let checked = decision.checkedKinds

        overridden.sessionWarmup.enabled = checked.contains(.sessionWarmup)
        overridden.cooldown.enabled = checked.contains(.cooldown)
        overridden.betweenSetRest.enabled = checked.contains(.betweenSetRest)
        overridden.exerciseWarmupSets.enabled = checked.contains(.exerciseWarmupSets)
        // AMA-2423 — mirrors betweenSetRest above; sends station_transition
        // prefs to mapper enrich, tombstoned via the generic reject path below.
        overridden.stationTransition.enabled = checked.contains(.stationTransition)

        // AMA-2378 Task 6 — door-screen edits only land when the kind is
        // checked; an unchecked kind keeps its standing activities/ramps
        // untouched (design §Surface 1 "retained config" — the sheet does not
        // need to clear its local state on toggle-off).
        if checked.contains(.sessionWarmup), let activities = decision.sessionWarmupActivities {
            overridden.sessionWarmup.activities = activities
        }
        if checked.contains(.cooldown), let activities = decision.cooldownActivities {
            overridden.cooldown.activities = activities
        }

        if checked.contains(.betweenSetRest),
           decision.restSecOverride != nil || decision.restOpenOverride != nil {
            let restOpen = decision.restOpenOverride ?? prefs.betweenSetRest.restOpen
            let restSec = restOpen ? nil : (decision.restSecOverride ?? prefs.betweenSetRest.restSec)
            try overridden.betweenSetRest.setRest(restSec: restSec, restOpen: restOpen)
        }

        // AMA-2423 — mirrors the betweenSetRest override above.
        if checked.contains(.stationTransition),
           decision.transitionSecOverride != nil || decision.transitionOpenOverride != nil {
            let transitionOpen = decision.transitionOpenOverride ?? prefs.stationTransition.transitionOpen
            let transitionSec = transitionOpen
                ? nil
                : (decision.transitionSecOverride ?? prefs.stationTransition.transitionSec)
            try overridden.stationTransition.setTransition(transitionSec: transitionSec, transitionOpen: transitionOpen)
        }

        // AMA-2408 F2 — opt-in ramps. Empty/nil `perExercise` no longer falls
        // through to global `default_sets` on every candidate. Row ON + empty
        // means ZERO ramps (every candidate excluded).
        if checked.contains(.exerciseWarmupSets) {
            let ramps = decision.perExerciseRamps ?? []
            applyPerExerciseRamps(ramps, plan: plan, into: &overridden.exerciseWarmupSets)
        }

        var remaining = tombstones
        let rejected = collectRejectedTombstones(
            plan: plan,
            checked: checked,
            into: &remaining
        )
        let cleared = clearReoptInTombstones(
            plan: plan,
            checked: checked,
            into: &remaining
        )

        return Application(
            prefs: overridden,
            tombstones: remaining,
            clearedTombstones: cleared,
            rejectedTombstones: rejected
        )
    }

    /// AMA-2408 F2 — opt-in only. An exercise gets warm-up sets ONLY when it
    /// has an enabled `PerExerciseRamp` the user created. Empty `ramps` + row
    /// ON → `perExercise = []` and every candidate lands in `excludeExerciseKeys`
    /// so the backend cannot revive the v1 global `default_sets` path.
    /// Disabled / never-touched candidates are excluded the same way.
    private static func applyPerExerciseRamps(
        _ ramps: [PerExerciseRamp],
        plan: Plan,
        into prefs: inout ExerciseWarmupSetsPrefs
    ) {
        // Keep intensity notes in persisted prefs (reopen honesty). Wire
        // sanitization happens in EnrichRequest.jsonObject() only.
        prefs.perExercise = ramps

        let configuredKeys = Set(ramps.map { ExerciseKeyNormalizer.normalize($0.exerciseRef) })
        let disabledKeys = ramps.filter { !$0.enabled }.map {
            ExerciseKeyNormalizer.normalize($0.exerciseRef)
        }
        let candidateNames = plan.offer(.exerciseWarmupSets)?.candidateExerciseNames ?? []
        let skippedKeys = candidateNames
            .map(ExerciseKeyNormalizer.normalize)
            .filter { !configuredKeys.contains($0) }

        var excludeKeys = Set(prefs.excludeExerciseKeys.map(ExerciseKeyNormalizer.normalize))
        excludeKeys.formUnion(disabledKeys)
        excludeKeys.formUnion(skippedKeys)
        // Empty opt-in list: exclude every candidate so default_sets cannot apply.
        if ramps.isEmpty {
            excludeKeys.formUnion(candidateNames.map(ExerciseKeyNormalizer.normalize))
        }
        // Re-enabled ramps must leave exclusions; otherwise confirm/reopen shows
        // an enabled exercise that still receives no warm-up after optInEffectiveRamps.
        let enabledKeys = ramps
            .filter(\.enabled)
            .map { ExerciseKeyNormalizer.normalize($0.exerciseRef) }
        excludeKeys.subtract(enabledKeys)
        prefs.excludeExerciseKeys = excludeKeys.sorted()
    }

    /// AMA-2346/2347 — tombstone only when a **default-checked** offer was turned off.
    private static func collectRejectedTombstones(
        plan: Plan,
        checked: Set<EnrichmentKind>,
        into remaining: inout [EnrichmentTombstone]
    ) -> [EnrichmentTombstone] {
        var rejected: [EnrichmentTombstone] = []
        for offer in plan.offers where !checked.contains(offer.kind) {
            guard offer.isChecked else { continue }
            if offer.kind == .exerciseWarmupSets {
                for exerciseId in offer.candidateExerciseIds {
                    let tomb = EnrichmentTombstone(kind: offer.kind, exerciseId: exerciseId)
                    guard !remaining.contains(tomb) else { continue }
                    remaining.append(tomb)
                    rejected.append(tomb)
                }
            } else if !WorkoutEnrichmentPresence.isTombstoned(offer.kind, tombstones: remaining) {
                let tomb = EnrichmentTombstone(kind: offer.kind)
                remaining.append(tomb)
                rejected.append(tomb)
            }
        }
        return rejected
    }

    /// Clear tombstones only for true re-opt-in (offer started unchecked).
    private static func clearReoptInTombstones(
        plan: Plan,
        checked: Set<EnrichmentKind>,
        into remaining: inout [EnrichmentTombstone]
    ) -> [EnrichmentTombstone] {
        var cleared: [EnrichmentTombstone] = []
        for kind in checked {
            guard let offer = plan.offer(kind), !offer.isChecked else { continue }
            if kind == .exerciseWarmupSets {
                for exerciseId in offer.tombstonedExerciseIds {
                    cleared.append(EnrichmentTombstone(kind: kind, exerciseId: exerciseId))
                    WorkoutEnrichmentMutations.clearTombstone(
                        &remaining,
                        kind: kind,
                        exerciseId: exerciseId
                    )
                }
            } else {
                cleared.append(EnrichmentTombstone(kind: kind))
                WorkoutEnrichmentMutations.clearTombstone(&remaining, kind: kind)
            }
        }
        return cleared
    }
}
