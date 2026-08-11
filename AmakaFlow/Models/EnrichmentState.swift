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

        enum CodingKeys: String, CodingKey {
            case checkedKinds = "checked_kinds"
            case mobilityActivities = "mobility_activities"
            case cooldownActivities = "cooldown_activities"
            case perExerciseRamps = "per_exercise_ramps"
            case restOpen = "rest_open"
            case restSec = "rest_sec"
        }

        var checkedKindSet: Set<EnrichmentKind> { Set(checkedKinds) }
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
                cooldownActivities: saved.cooldownActivities.isEmpty
                    ? WorkoutEnrichmentMutations.defaultCooldownActivities()
                    : saved.cooldownActivities,
                // Late-added exercises: absent from perExerciseRamps → unchecked.
                perExerciseRamps: saved.perExerciseRamps,
                restOpen: saved.restOpen,
                restSec: WorkoutEnrichmentPushCopy.normalizedRestSec(saved.restSec),
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
            candidateExerciseNames: candidateExerciseNames,
            target: target
        )
    }

    /// Convenience: seed from a push plan + standing globals + optional save.
    static func seed(
        workoutPrefs: Persisted?,
        globalDefaults: WorkoutPreferences,
        plan: WorkoutEnrichmentPushPlanner.Plan
    ) -> EnrichmentState {
        seed(
            workoutPrefs: workoutPrefs,
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
            restSec: restSec
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
            perExerciseRamps: checkedKinds.contains(.exerciseWarmupSets) ? perExerciseRamps : nil
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
        }
    }

    func summary(for row: WatchItemReadinessRow) -> String? {
        switch row {
        case .mobility: return summary(for: EnrichmentKind.sessionWarmup)
        case .warmups: return summary(for: EnrichmentKind.exerciseWarmupSets)
        case .rest: return summary(for: EnrichmentKind.betweenSetRest)
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
        if readiness.cooldownEnabled { kinds.append(.cooldown) }
        return EnrichmentState.Persisted(
            checkedKinds: kinds,
            mobilityActivities: config.mobilityActivities,
            cooldownActivities: config.cooldownActivities,
            perExerciseRamps: config.perExerciseRamps,
            restOpen: config.restOpen,
            restSec: config.restSec
        )
    }

    func asReadiness() -> WatchItemReadinessState {
        WatchItemReadinessState(
            mobilityEnabled: checkedKindSet.contains(.sessionWarmup),
            warmupsEnabled: checkedKindSet.contains(.exerciseWarmupSets),
            restEnabled: checkedKindSet.contains(.betweenSetRest),
            cooldownEnabled: checkedKindSet.contains(.cooldown)
        )
    }

    func asConfig() -> WatchItemConfigState {
        WatchItemConfigState(
            mobilityActivities: mobilityActivities,
            cooldownActivities: cooldownActivities,
            perExerciseRamps: perExerciseRamps,
            restOpen: restOpen,
            restSec: restSec
        )
    }
}
