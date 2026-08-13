//
//  LogbookRollup.swift
//  AmakaFlow
//
//  AMA-2426: Quick ↔ set-by-set mutual conversion — no data loss either direction.
//

import Foundation

enum LogbookRollup {
    /// Derive exercise-level aggregates from checked sets. Unchecked targets excluded.
    static func rollup(from sets: [SetActual], planned: ExerciseActualPlanned) -> (
        actualSets: Int,
        actualReps: Int,
        actualWeightKg: Double?
    ) {
        let checked = sets.filter(\.isChecked).sorted { $0.index < $1.index }
        guard !checked.isEmpty else {
            return (0, planned.reps, nil)
        }
        let last = checked.last!
        return (
            actualSets: checked.count,
            actualReps: last.reps ?? planned.reps,
            actualWeightKg: last.weightKg ?? planned.weightKg
        )
    }

    /// Expand Quick-mode aggregates into set rows. Confirmed exercises mark sets checked.
    static func expandSets(from exercise: ExerciseActual, now: Date = Date()) -> [SetActual] {
        if !exercise.sets.isEmpty {
            return exercise.sets.sorted { lhs, rhs in
                if lhs.isWarmup != rhs.isWarmup { return lhs.isWarmup && !rhs.isWarmup }
                return lhs.index < rhs.index
            }
        }

        let count = max(exercise.actualSets, exercise.planned.sets, 1)
        let checked = exercise.confirmation != nil
        return (1...count).map { index in
            SetActual(
                index: index,
                isWarmup: false,
                weightKg: exercise.actualWeightKg ?? exercise.planned.weightKg,
                reps: exercise.actualReps,
                checkedAt: checked ? now : nil
            )
        }
    }

    /// Apply set-by-set data onto an ExerciseActual and refresh aggregates.
    static func applySets(_ sets: [SetActual], to exercise: inout ExerciseActual) {
        let sorted = sets.sorted { lhs, rhs in
            if lhs.isWarmup != rhs.isWarmup { return lhs.isWarmup && !rhs.isWarmup }
            return lhs.index < rhs.index
        }
        exercise.sets = sorted
        let rolled = rollup(from: sorted, planned: exercise.planned)
        exercise.actualSets = rolled.actualSets
        exercise.actualReps = rolled.actualReps
        exercise.actualWeightKg = rolled.actualWeightKg
        if rolled.actualSets > 0 {
            let matchesPlan =
                rolled.actualSets == exercise.planned.sets
                && rolled.actualReps == exercise.planned.reps
                && rolled.actualWeightKg == exercise.planned.weightKg
            exercise.confirmation = matchesPlan ? .asPlanned : .adjusted
        }
    }

    /// Build Logbook entries from a fill-in session (after mode / mode switch).
    static func entries(
        from session: ActualsFillInSession,
        ghostLookup: ActualsGhostLookingUp? = nil
    ) -> [LogbookExerciseEntry] {
        session.exercises.map { exercise in
            let sets = expandSets(from: exercise)
            let lastActual = try? ghostLookup?.latestActual(exerciseKey: exercise.id)
            let ghosts = LogbookGhosts.ghosts(
                setCount: sets.count,
                planned: exercise.planned,
                lastSetActuals: nil,
                lastExerciseActual: lastActual
            )
            let partner = supersetPartner(for: exercise, in: session.exercises)
            return LogbookExerciseEntry(
                id: exercise.id,
                name: exercise.name,
                planned: exercise.planned,
                sets: sets,
                ghosts: ghosts,
                structureHeader: exercise.structureHeader,
                structureBlockIndex: exercise.structureBlockIndex,
                supersetPartner: partner
            )
        }
    }

    /// Convert a draft into an ActualsFillInSession for the verified pipeline.
    static func fillInSession(from draft: LogDraft, verified: Bool = false) -> ActualsFillInSession {
        let exercises: [ExerciseActual] = draft.entries.map { entry in
            var exercise = ExerciseActual(
                id: entry.id,
                name: entry.name,
                planned: entry.planned,
                structureHeader: entry.structureHeader,
                structureBlockIndex: entry.structureBlockIndex
            )
            applySets(entry.sets, to: &exercise)
            // Target-pass: if nothing checked, leave unconfirmed so save gate can require checks
            // or caller marks confirmation when committing standalone with zero checks.
            if exercise.actualSets == 0 {
                exercise.confirmation = nil
                exercise.actualSets = 0
                exercise.actualReps = entry.planned.reps
                exercise.actualWeightKg = nil
            }
            return exercise
        }
        return ActualsFillInSession(
            id: draft.attachedSessionId ?? draft.id,
            title: draft.title,
            subtitle: draft.subtitle,
            exercises: exercises,
            rpe: draft.rpe,
            verified: verified,
            structureBody: nil
        )
    }

    /// Persist unchecked targets as the workout's load plan (next ghosts), exclude from actuals.
    static func loadPlanTargets(from entry: LogbookExerciseEntry) -> [SetActual] {
        entry.sets
            .filter { !$0.isChecked && ($0.weightKg != nil || $0.reps != nil) }
            .map {
                SetActual(
                    index: $0.index,
                    isWarmup: $0.isWarmup,
                    weightKg: $0.weightKg,
                    reps: $0.reps,
                    checkedAt: nil
                )
            }
    }

    /// Actuals payload for save — checked sets only.
    static func actualsForSave(from entry: LogbookExerciseEntry) -> [SetActual] {
        entry.sets.filter(\.isChecked)
    }

    private static func supersetPartner(
        for exercise: ExerciseActual,
        in exercises: [ExerciseActual]
    ) -> String? {
        guard let header = exercise.structureHeader?.uppercased(),
              header.contains("SUPERSET"),
              let block = exercise.structureBlockIndex else {
            return nil
        }
        let peers = exercises.filter {
            $0.structureBlockIndex == block && $0.id != exercise.id
        }
        return peers.first?.name
    }
}
