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
    case applyRampToAll(sets: [RampSet])
    case replaceRamps([PerExerciseRamp])
    case confirm
    case skip
}

enum EnrichmentReducer {
    /// Pure reduce. `confirm` / `skip` are no-ops on state (persistence is the
    /// caller's job) so round-trip tests can `reduce → persist → seed` freely.
    static func reduce(_ state: EnrichmentState, _ action: EnrichmentAction) -> EnrichmentState {
        var next = state
        switch action {
        case .toggleRow(let kind):
            if next.checkedKinds.contains(kind) {
                next.checkedKinds.remove(kind)
            } else {
                next.checkedKinds.insert(kind)
            }

        case .setRamp(let exercise, let ramp):
            let key = ExerciseKeyNormalizer.normalize(exercise)
            if let index = next.perExerciseRamps.firstIndex(where: {
                ExerciseKeyNormalizer.normalize($0.exerciseRef) == key
            }) {
                next.perExerciseRamps[index] = ramp
            } else {
                next.perExerciseRamps.append(ramp)
            }

        case .toggleExercise(let name):
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

        case .setSequence(let kind, let steps):
            switch kind {
            case .mobility: next.mobilityActivities = steps
            case .cooldown: next.cooldownActivities = steps
            }

        case .setRest(let open, let sec):
            next.restOpen = open
            next.restSec = WorkoutEnrichmentPushCopy.normalizedRestSec(sec)

        case .applyRampToAll(let sets):
            next.perExerciseRamps = WorkoutEnrichmentMutations.applyRampSets(
                sets,
                toEnabledRampsIn: next.perExerciseRamps
            )

        case .replaceRamps(let ramps):
            next.perExerciseRamps = ramps

        case .confirm, .skip:
            break
        }
        return next
    }

    static func reduce(_ state: EnrichmentState, actions: [EnrichmentAction]) -> EnrichmentState {
        actions.reduce(state, reduce)
    }
}
