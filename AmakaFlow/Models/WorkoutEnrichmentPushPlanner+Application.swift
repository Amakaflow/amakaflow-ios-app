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

        init(
            checkedKinds: Set<EnrichmentKind>,
            restSecOverride: Int? = nil,
            restOpenOverride: Bool? = nil,
            sessionWarmupActivities: [EnrichmentActivityPref]? = nil,
            cooldownActivities: [EnrichmentActivityPref]? = nil,
            perExerciseRamps: [PerExerciseRamp]? = nil
        ) {
            self.checkedKinds = checkedKinds
            self.restSecOverride = restSecOverride
            self.restOpenOverride = restOpenOverride
            self.sessionWarmupActivities = sessionWarmupActivities
            self.cooldownActivities = cooldownActivities
            self.perExerciseRamps = perExerciseRamps
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

        if checked.contains(.exerciseWarmupSets), let ramps = decision.perExerciseRamps, !ramps.isEmpty {
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

    /// AMA-2378 Task 6 — full `per_exercise` list wins over the v1 global
    /// `default_sets` + `exclude_exercise_keys` scheme (backend "prefer
    /// per_exercise when non-empty"). Candidates the user left disabled, or
    /// never touched in the warm-up pick screen at all ("skipped"), are also
    /// folded into `excludeExerciseKeys` so they never fall back to the
    /// global default — an absent/disabled `per_exercise` entry means "no
    /// warm-up sets for this exercise", not "use the global default".
    private static func applyPerExerciseRamps(
        _ ramps: [PerExerciseRamp],
        plan: Plan,
        into prefs: inout ExerciseWarmupSetsPrefs
    ) {
        prefs.perExercise = ramps

        let configuredKeys = Set(ramps.map { ExerciseKeyNormalizer.normalize($0.exerciseRef) })
        let disabledNames = ramps.filter { !$0.enabled }.map(\.exerciseRef)
        let candidateNames = plan.offer(.exerciseWarmupSets)?.candidateExerciseNames ?? []
        let skippedNames = candidateNames.filter {
            !configuredKeys.contains(ExerciseKeyNormalizer.normalize($0))
        }

        var excludeKeys = Set(prefs.excludeExerciseKeys)
        excludeKeys.formUnion(disabledNames)
        excludeKeys.formUnion(skippedNames)
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
