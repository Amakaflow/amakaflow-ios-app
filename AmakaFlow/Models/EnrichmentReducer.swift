//
//  EnrichmentReducer.swift
//  AmakaFlow
//
//  AMA-2408 F4 — pure `(EnrichmentState, EnrichmentAction) → EnrichmentState`.
//  Sheets are dumb renderers + action dispatchers; no seed logic in SwiftUI init.
//

import Foundation

enum EnrichmentAction: Equatable, Sendable {
    case toggleRow(EnrichmentKind)
    case setRamp(exercise: String, ramp: PerExerciseRamp)
    case toggleExercise(String)
    case setSequence(EnrichmentSequenceKind, [EnrichmentActivityPref])
    case setRest(open: Bool, sec: Int)
    /// AMA-2423 — Transitions row segmented control, parallel to `setRest`.
    case setStationTransition(open: Bool, sec: Int)
    case applyRampToAll(sets: [RampSet])
    case replaceRamps([PerExerciseRamp])
    case confirm
    case skip
}

enum EnrichmentReducer {
    /// Pure reduce. `confirm` / `skip` are no-ops on state (persistence is the
    /// caller's job) so round-trip tests can `reduce → persist → seed` freely.
    static func reduce(_ state: EnrichmentState, _ action: EnrichmentAction) -> EnrichmentState {
        switch action {
        case .toggleRow(let kind):
            return toggleRow(state, kind: kind)
        case .setRamp(let exercise, let ramp):
            return setRamp(state, exercise: exercise, ramp: ramp)
        case .toggleExercise(let name):
            return toggleExercise(state, name: name)
        case .setSequence(let kind, let steps):
            return setSequence(state, kind: kind, steps: steps)
        case .setRest(let open, let sec):
            return setRest(state, open: open, sec: sec)
        case .setStationTransition(let open, let sec):
            return setStationTransition(state, open: open, sec: sec)
        case .applyRampToAll(let sets):
            return applyRampToAll(state, sets: sets)
        case .replaceRamps(let ramps):
            return replaceRamps(state, ramps: ramps)
        case .confirm, .skip:
            return state
        }
    }

    static func reduce(_ state: EnrichmentState, actions: [EnrichmentAction]) -> EnrichmentState {
        actions.reduce(state, reduce)
    }

    // MARK: - Action helpers (keep `reduce` a thin dispatcher)

    private static func toggleRow(_ state: EnrichmentState, kind: EnrichmentKind) -> EnrichmentState {
        var next = state
        if next.checkedKinds.contains(kind) {
            next.checkedKinds.remove(kind)
        } else {
            next.checkedKinds.insert(kind)
        }
        return next
    }

    private static func setRamp(
        _ state: EnrichmentState,
        exercise: String,
        ramp: PerExerciseRamp
    ) -> EnrichmentState {
        var next = state
        let key = ExerciseKeyNormalizer.normalize(exercise)
        if let index = next.perExerciseRamps.firstIndex(where: {
            ExerciseKeyNormalizer.normalize($0.exerciseRef) == key
        }) {
            next.perExerciseRamps[index] = ramp
        } else {
            next.perExerciseRamps.append(ramp)
        }
        return next
    }

    private static func toggleExercise(_ state: EnrichmentState, name: String) -> EnrichmentState {
        var next = state
        let key = ExerciseKeyNormalizer.normalize(name)
        if let index = next.perExerciseRamps.firstIndex(where: {
            ExerciseKeyNormalizer.normalize($0.exerciseRef) == key
        }) {
            next.perExerciseRamps[index].enabled.toggle()
            if next.perExerciseRamps[index].enabled,
               next.perExerciseRamps[index].sets.isEmpty {
                next.perExerciseRamps[index].sets = WorkoutEnrichmentMutations.defaultRampSets()
            }
        } else {
            // First enable — seed 8/5 (opt-in). Untouched stays absent.
            next.perExerciseRamps.append(PerExerciseRamp(
                exerciseRef: name,
                enabled: true,
                sets: WorkoutEnrichmentMutations.defaultRampSets()
            ))
        }
        return next
    }

    private static func setSequence(
        _ state: EnrichmentState,
        kind: EnrichmentSequenceKind,
        steps: [EnrichmentActivityPref]
    ) -> EnrichmentState {
        var next = state
        switch kind {
        case .mobility: next.mobilityActivities = steps
        case .cooldown: next.cooldownActivities = steps
        }
        return next
    }

    private static func setRest(_ state: EnrichmentState, open: Bool, sec: Int) -> EnrichmentState {
        var next = state
        next.restOpen = open
        next.restSec = WorkoutEnrichmentPushCopy.normalizedRestSec(sec)
        return next
    }

    private static func setStationTransition(
        _ state: EnrichmentState,
        open: Bool,
        sec: Int
    ) -> EnrichmentState {
        var next = state
        next.transitionOpen = open
        next.transitionSec = WorkoutEnrichmentPushCopy.normalizedTransitionSec(sec)
        return next
    }

    private static func applyRampToAll(_ state: EnrichmentState, sets: [RampSet]) -> EnrichmentState {
        var next = state
        next.perExerciseRamps = WorkoutEnrichmentMutations.applyRampSets(
            sets,
            toEnabledRampsIn: next.perExerciseRamps
        )
        return next
    }

    private static func replaceRamps(_ state: EnrichmentState, ramps: [PerExerciseRamp]) -> EnrichmentState {
        var next = state
        next.perExerciseRamps = ramps
        return next
    }
}
