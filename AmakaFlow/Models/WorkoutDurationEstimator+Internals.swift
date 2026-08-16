//
//  WorkoutDurationEstimator+Internals.swift
//  AmakaFlow
//
//  AMA-2395 — block/step estimation helpers (split for SwiftLint type_body_length).
//

import Foundation

extension WorkoutDurationEstimator {
    struct SignalFlags {
        var sawTimed = false
        var sawDistance = false
        var sawReps = false
        var sawSetsOnly = false
        var restSamples: [Int] = []

        mutating func merge(_ other: SignalFlags) {
            if other.sawTimed { sawTimed = true }
            if other.sawDistance { sawDistance = true }
            if other.sawReps { sawReps = true }
            if other.sawSetsOnly { sawSetsOnly = true }
            restSamples.append(contentsOf: other.restSamples)
        }
    }

    struct BlockEstimate {
        var seconds: Int
        var activeSeconds: Int
        var isEstimate: Bool
        var exercises: [WorkoutExerciseDuration]
        var openNames: [String]
        var flags: SignalFlags
    }

    struct StepEstimate {
        var row: WorkoutExerciseDuration
        var totalSeconds: Int
        var activeSeconds: Int
        var isEstimate: Bool
        var flags: SignalFlags
        var restUsed: Int?
    }

    static func estimateBlock(_ block: Block) -> BlockEstimate {
        if let cap = capSeconds(for: block) {
            return cappedBlock(block, capSeconds: cap)
        }

        let multiStation = isMultiStation(block)
        let roundsMultiplier = multiStation ? max(1, block.rounds) : 1
        var roundWork = 0
        var roundActive = 0
        var roundEstimate = false
        var exerciseRows: [WorkoutExerciseDuration] = []
        var openNames: [String] = []
        var flags = SignalFlags()

        for (index, exercise) in block.exercises.enumerated() {
            let step = estimateExercise(
                exercise,
                block: block,
                isLastInRound: index == block.exercises.count - 1,
                multiStation: multiStation
            )
            exerciseRows.append(step.row)
            if step.row.isOpen {
                openNames.append(exercise.name)
            } else {
                roundWork += step.totalSeconds
                roundActive += step.activeSeconds
                if step.isEstimate { roundEstimate = true }
                flags.merge(step.flags)
                if let rest = step.restUsed { flags.restSamples.append(rest) }
            }
        }

        let between = max(0, block.restBetweenSeconds ?? 0)
        let betweenTotal = between * max(0, roundsMultiplier - 1)

        return BlockEstimate(
            seconds: roundWork * roundsMultiplier + betweenTotal,
            activeSeconds: roundActive * roundsMultiplier,
            isEstimate: roundEstimate,
            exercises: exerciseRows,
            openNames: openNames,
            flags: flags
        )
    }

    static func isMultiStation(_ block: Block) -> Bool {
        guard block.exercises.count > 1 else { return false }
        switch block.structure {
        case .circuit, .timedCircuit, .superset, .amrap, .emom, .tabata, .fortime:
            return true
        case .straight, .warmup, .cooldown:
            // Straight lists keep per-exercise sets / rounds-as-sets — never
            // treat them as a multi-station circuit for duration math.
            return false
        }
    }

    static func cappedBlock(_ block: Block, capSeconds: Int) -> BlockEstimate {
        let count = max(1, block.exercises.count)
        var share = Array(repeating: capSeconds / count, count: count)
        let remainder = capSeconds - share.reduce(0, +)
        for index in 0..<remainder { share[index] += 1 }

        let rows: [WorkoutExerciseDuration] = zip(block.exercises, share).map { exercise, seconds in
            WorkoutExerciseDuration(
                exerciseId: exercise.id,
                seconds: seconds,
                isEstimate: false,
                isOpen: false
            )
        }
        return BlockEstimate(
            seconds: capSeconds,
            activeSeconds: capSeconds,
            isEstimate: false,
            exercises: rows,
            openNames: [],
            flags: SignalFlags(sawTimed: true)
        )
    }

    static func capSeconds(for block: Block) -> Int? {
        switch block.structure {
        case .emom, .amrap, .fortime:
            let allTimed = block.exercises.allSatisfy { ($0.durationSeconds ?? 0) > 0 }
            if allTimed { return nil }
            return max(1, block.rounds) * 60
        case .tabata:
            let allTimed = block.exercises.allSatisfy { ($0.durationSeconds ?? 0) > 0 }
            if allTimed { return nil }
            // Converter default: 20s work + 10s rest per exercise per round.
            return max(1, block.rounds) * max(1, block.exercises.count) * 30
        case .straight, .superset, .circuit, .timedCircuit, .warmup, .cooldown:
            return nil
        }
    }

    static func estimateExercise(
        _ exercise: Exercise,
        block: Block,
        isLastInRound: Bool,
        multiStation: Bool
    ) -> StepEstimate {
        if let duration = exercise.durationSeconds, duration > 0 {
            return timedStep(exercise, duration: duration, block: block, multiStation: multiStation, isLastInRound: isLastInRound)
        }
        if let meters = exercise.distance, meters > 0 {
            return distanceStep(exercise, meters: meters, block: block, multiStation: multiStation, isLastInRound: isLastInRound)
        }
        let (plainReps, range) = RepsRange.splitPrescription(exercise.reps)
        let repsValue = plainReps ?? range.map { ($0.low + $0.high) / 2 }
        if let reps = repsValue, reps > 0 {
            return repsStep(exercise, reps: reps, block: block, multiStation: multiStation, isLastInRound: isLastInRound)
        }
        // Sets known but no timed / distance / reps target → 1 min work + 1 min rest
        // per set (rest = the between-set minute). No sets and no target → open.
        if let explicitSets = exercise.sets, explicitSets > 0 {
            return setsOnlyStep(exercise, sets: explicitSets)
        }
        return StepEstimate(
            row: WorkoutExerciseDuration(
                exerciseId: exercise.id,
                seconds: 0,
                isEstimate: false,
                isOpen: true
            ),
            totalSeconds: 0,
            activeSeconds: 0,
            isEstimate: false,
            flags: SignalFlags(),
            restUsed: nil
        )
    }

    /// Undefined prescription with a set count: 1 min work + 1 min rest per set.
    private static func setsOnlyStep(_ exercise: Exercise, sets: Int) -> StepEstimate {
        let setCount = max(1, sets)
        let work = undefinedSetWorkSeconds * setCount
        let rest = undefinedSetRestSeconds * setCount
        return StepEstimate(
            row: WorkoutExerciseDuration(
                exerciseId: exercise.id,
                seconds: work + rest,
                isEstimate: true,
                isOpen: false
            ),
            totalSeconds: work + rest,
            activeSeconds: work,
            isEstimate: true,
            flags: SignalFlags(sawSetsOnly: true, restSamples: [undefinedSetRestSeconds]),
            restUsed: undefinedSetRestSeconds
        )
    }

    private static func timedStep(
        _ exercise: Exercise,
        duration: Int,
        block: Block,
        multiStation: Bool,
        isLastInRound: Bool
    ) -> StepEstimate {
        let sets = effectiveSets(exercise, block: block)
        let work = duration * sets
        let rest = restSeconds(
            for: exercise,
            sets: sets,
            multiStation: multiStation,
            isLastInRound: isLastInRound,
            repsHint: nil
        )
        return StepEstimate(
            row: WorkoutExerciseDuration(
                exerciseId: exercise.id,
                seconds: work + rest,
                isEstimate: false,
                isOpen: false
            ),
            totalSeconds: work + rest,
            activeSeconds: work,
            isEstimate: false,
            flags: SignalFlags(sawTimed: true),
            restUsed: rest > 0 ? exercise.restSeconds : nil
        )
    }

    private static func distanceStep(
        _ exercise: Exercise,
        meters: Double,
        block: Block,
        multiStation: Bool,
        isLastInRound: Bool
    ) -> StepEstimate {
        let sets = effectiveSets(exercise, block: block)
        let work = WorkoutPaceTable.seconds(forMeters: meters, exerciseName: exercise.name) * sets
        let rest = restSeconds(
            for: exercise,
            sets: sets,
            multiStation: multiStation,
            isLastInRound: isLastInRound,
            repsHint: nil
        )
        return StepEstimate(
            row: WorkoutExerciseDuration(
                exerciseId: exercise.id,
                seconds: work + rest,
                isEstimate: true,
                isOpen: false
            ),
            totalSeconds: work + rest,
            activeSeconds: work,
            isEstimate: true,
            flags: SignalFlags(sawDistance: true),
            restUsed: nil
        )
    }

    private static func repsStep(
        _ exercise: Exercise,
        reps: Int,
        block: Block,
        multiStation: Bool,
        isLastInRound: Bool
    ) -> StepEstimate {
        let sets = effectiveSets(exercise, block: block)
        let work = (reps * secondsPerRep + setupSecondsPerSet) * sets
        let rest = restSeconds(
            for: exercise,
            sets: sets,
            multiStation: multiStation,
            isLastInRound: isLastInRound,
            repsHint: reps
        )
        return StepEstimate(
            row: WorkoutExerciseDuration(
                exerciseId: exercise.id,
                seconds: work + rest,
                isEstimate: true,
                isOpen: false
            ),
            totalSeconds: work + rest,
            activeSeconds: work,
            isEstimate: true,
            flags: SignalFlags(sawReps: true),
            // Report only rest that was actually added to the total.
            restUsed: rest > 0 ? rest / max(1, sets) : nil
        )
    }

    static func effectiveSets(_ exercise: Exercise, block: Block) -> Int {
        // Multi-station rounds already multiply the station sequence — ignore
        // per-exercise sets so imports that keep both don't double-count.
        if isMultiStation(block) { return 1 }
        if let sets = exercise.sets, sets > 0 { return sets }
        return max(1, block.rounds)
    }

    static func restSeconds(
        for exercise: Exercise,
        sets: Int,
        multiStation: Bool,
        isLastInRound: Bool,
        repsHint: Int?
    ) -> Int {
        if multiStation {
            guard isLastInRound, let explicit = exercise.restSeconds else { return 0 }
            return max(0, explicit)
        }

        let perSet: Int
        if let explicit = exercise.restSeconds {
            perSet = max(0, explicit)
        } else if let reps = repsHint, reps <= heavyRepThreshold {
            perSet = heavyRestSeconds
        } else if repsHint != nil {
            perSet = defaultRestSeconds
        } else {
            perSet = 0
        }
        return perSet * max(0, sets)
    }

    static func fallbackStored(_ stored: Int) -> WorkoutDurationEstimate {
        let seconds = max(0, stored)
        return WorkoutDurationEstimate(
            totalSec: seconds,
            activeSec: seconds,
            isEstimate: seconds > 0,
            perSection: [],
            perExercise: [],
            basisNote: seconds > 0 ? "STORED DURATION · NO STRUCTURE TO MEASURE" : "NO STRUCTURE",
            activeSublabel: seconds > 0 ? "STORED · ESTIMATED" : "—"
        )
    }

    static func basisNote(flags: SignalFlags, openNames: [String], isEstimate: Bool) -> String {
        var parts: [String] = []
        if flags.sawDistance {
            parts.append("ESTIMATED FROM DISTANCES AT DEFAULT PACES")
        } else if flags.sawSetsOnly {
            parts.append("≈ 1 MIN WORK + 1 MIN REST / SET (NO TARGET DEFINED)")
        } else if flags.sawReps {
            let rest = flags.restSamples.first ?? defaultRestSeconds
            parts.append("≈ SETS × (REPS × 3S + SETUP) + REST \(rest)S/SET")
        } else if flags.sawTimed, !isEstimate {
            parts.append("ALL STEPS TIMED")
        } else if isEstimate {
            parts.append("ESTIMATED FROM STRUCTURE")
        }
        if !openNames.isEmpty {
            parts.append("+ OPEN STEPS")
        }
        return parts.joined(separator: " · ")
    }

    static func activeSublabel(flags: SignalFlags, isEstimate: Bool) -> String {
        if flags.sawTimed, !isEstimate, !flags.sawDistance, !flags.sawReps, !flags.sawSetsOnly {
            return "ALL TIMED · EXACT"
        }
        if flags.sawDistance {
            return "WORK · PACES: DEFAULT"
        }
        if flags.sawSetsOnly {
            return "SETS · 1 MIN WORK + 1 MIN REST"
        }
        if flags.sawReps {
            let rest = flags.restSamples.first ?? defaultRestSeconds
            return "LIFTING · REST \(rest)S"
        }
        return isEstimate ? "WORK · ESTIMATED" : "WORK · EXACT"
    }
}
