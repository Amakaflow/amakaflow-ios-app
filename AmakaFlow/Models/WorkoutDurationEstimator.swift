//
//  WorkoutDurationEstimator.swift
//  AmakaFlow
//
//  AMA-2395 — real duration estimation, replacing the meaningless "~1 MIN"
//  meta that shipped on hour-long workouts.
//
//  Pure function: workout structure → total / active seconds, an exact-vs-≈
//  flag, per-block and per-exercise breakdowns, and a plain-language basis
//  note. No I/O, no dates, no view state — every surface (detail, pre-save
//  preview, library rows, collection rows) reads the same numbers from here.
//
//  v1 uses a fixed per-modality pace table. AMA-2387's actuals loop will feed
//  real user paces in v2 — `WorkoutPaceTable` is the seam for that; nothing
//  else in this file needs to change.
//

import Foundation

// MARK: - Output

/// One estimated span (a block or an exercise) with its own exactness flag.
struct WorkoutDurationComponent: Equatable, Identifiable {
    /// `Block.id` or `Exercise.id`.
    let id: String
    let seconds: Int
    let isEstimate: Bool
}

struct WorkoutDurationEstimate: Equatable {
    /// Work + rest + transitions.
    let totalSec: Int
    /// Work only — rest and transition padding excluded.
    let activeSec: Int
    /// True iff ANY component was estimated rather than read off a timed step.
    let isEstimate: Bool
    /// Per source block, in source order.
    let perSection: [WorkoutDurationComponent]
    /// Per exercise, in source order.
    let perExercise: [WorkoutDurationComponent]
    /// Mono footnote under the TIME card, e.g.
    /// `ESTIMATED FROM DISTANCES AT DEFAULT PACES` or
    /// `≈ SETS × (REPS × 3S + SETUP) + REST 60S/SET · + OPEN STEPS`.
    let basisNote: String
    /// Sublabel for the ACTIVE cell, e.g. `ALL TIMED · EXACT`, `LIFTING · REST 90S`.
    let activeNote: String
    /// True when a step had no knowable target (open goal) and was excluded.
    let hasOpenSteps: Bool

    static let empty = WorkoutDurationEstimate(
        totalSec: 0,
        activeSec: 0,
        isEstimate: false,
        perSection: [],
        perExercise: [],
        basisNote: "NO STRUCTURE YET",
        activeNote: "NOT SET",
        hasOpenSteps: false
    )

    /// Last resort for a workout with no structure to read: its own saved
    /// duration, flagged as an estimate because nothing here was derived.
    static func fromStoredDuration(_ seconds: Int) -> WorkoutDurationEstimate {
        WorkoutDurationEstimate(
            totalSec: max(0, seconds),
            activeSec: max(0, seconds),
            isEstimate: true,
            perSection: [],
            perExercise: [],
            basisNote: "AS SAVED · NO STRUCTURE TO MEASURE",
            activeNote: "AS SAVED",
            hasOpenSteps: false
        )
    }

    func seconds(forBlockID id: String) -> WorkoutDurationComponent? {
        perSection.first { $0.id == id }
    }

    func seconds(forExerciseID id: String) -> WorkoutDurationComponent? {
        perExercise.first { $0.id == id }
    }

    /// Sum of the named blocks — how a semantic band that spans more than one
    /// source block gets its subtotal.
    func component(forBlockIDs ids: [String]) -> WorkoutDurationComponent {
        let parts = ids.compactMap { seconds(forBlockID: $0) }
        return WorkoutDurationComponent(
            id: ids.joined(separator: "+"),
            seconds: parts.reduce(0) { $0 + $1.seconds },
            isEstimate: parts.contains { $0.isEstimate }
        )
    }

    /// Sum of the named exercises — a band that folds rows from several blocks.
    func component(forExerciseIDs ids: [String]) -> WorkoutDurationComponent {
        let parts = ids.compactMap { seconds(forExerciseID: $0) }
        return WorkoutDurationComponent(
            id: ids.joined(separator: "+"),
            seconds: parts.reduce(0) { $0 + $1.seconds },
            isEstimate: parts.contains { $0.isEstimate }
        )
    }
}

// MARK: - Pace table (AMA-2387 v2 seam)

/// Seconds per metre by cardio-machine kind. v1 ships fixed defaults; v2 will
/// build this from the user's recent actuals and everything downstream is
/// already written against the protocol.
protocol WorkoutPaceTable {
    func secondsPerMetre(forMachineKind kind: String?) -> Double
    /// Whether these paces came from the user's own history (drives copy:
    /// "DEFAULT PACES" vs "YOUR RECENT PACES" — never claim the latter falsely).
    var isPersonalised: Bool { get }
}

struct DefaultWorkoutPaceTable: WorkoutPaceTable {
    var isPersonalised: Bool { false }

    func secondsPerMetre(forMachineKind kind: String?) -> Double {
        switch kind {
        case "row": return 120.0 / 500.0        // 500 m in 2:00
        case "ski": return 130.0 / 500.0        // 500 m in 2:10
        case "bike": return 105.0 / 1000.0      // 1 km in 1:45
        case "treadmill": return 330.0 / 1000.0 // same as run
        case "run": return 330.0 / 1000.0       // 1 km in 5:30
        default: return 150.0 / 500.0           // unknown machine
        }
    }
}

// MARK: - Estimator

enum WorkoutDurationEstimator {
    /// Seconds of work assumed per rep.
    static let secondsPerRep = 3
    /// Setup / unrack / get-into-position, charged once per set.
    static let setupSecondsPerSet = 15
    /// Default rest between strength sets when the step doesn't say.
    static let defaultRestSeconds = 60
    /// Heavier work (≤ this many reps) rests longer.
    static let heavyRestSeconds = 90
    static let heavyRepsThreshold = 6
    /// Padding for rotating between stations. Only ever applied to a block that
    /// is ALREADY an estimate — see `blockDuration(_:)`.
    static let transitionFactor = 1.05

    static func estimate(
        for workout: Workout,
        paceTable: WorkoutPaceTable = DefaultWorkoutPaceTable()
    ) -> WorkoutDurationEstimate {
        let structural = estimate(blocks: workout.blocks, paceTable: paceTable)
        // Structure always wins: a saved `duration` of 60s on a ten-round
        // workout is exactly what produced "~1 MIN". Only when there is no
        // structure at all do we fall back to what the workout says about
        // itself — and we still mark it as an estimate.
        guard structural.isUnknown, workout.duration > 0 else { return structural }
        return .fromStoredDuration(workout.duration)
    }

    static func estimate(
        blocks: [Block],
        paceTable: WorkoutPaceTable = DefaultWorkoutPaceTable()
    ) -> WorkoutDurationEstimate {
        let populated = blocks.filter { !$0.exercises.isEmpty }
        guard !populated.isEmpty else { return .empty }

        var perSection: [WorkoutDurationComponent] = []
        var perExercise: [WorkoutDurationComponent] = []
        var totalSec = 0
        var activeSec = 0
        var tally = BasisTally()

        for block in populated {
            let measured = blockDuration(block, paceTable: paceTable, tally: &tally)
            perSection.append(
                WorkoutDurationComponent(
                    id: block.id,
                    seconds: measured.totalSec,
                    isEstimate: measured.isEstimate
                )
            )
            perExercise.append(contentsOf: measured.perExercise)
            totalSec += measured.totalSec
            activeSec += measured.activeSec
        }

        return WorkoutDurationEstimate(
            totalSec: totalSec,
            activeSec: activeSec,
            isEstimate: tally.hasEstimate,
            perSection: perSection,
            perExercise: perExercise,
            basisNote: tally.basisNote(paceTable: paceTable),
            activeNote: tally.activeNote,
            hasOpenSteps: tally.hasOpenSteps
        )
    }

    // MARK: - Blocks

    private struct BlockDuration {
        var totalSec = 0
        var activeSec = 0
        var isEstimate = false
        var perExercise: [WorkoutDurationComponent] = []
    }

    private static func blockDuration(
        _ block: Block,
        paceTable: WorkoutPaceTable,
        tally: inout BasisTally
    ) -> BlockDuration {
        let rounds = max(1, block.rounds)

        // Capped structures are exact by definition: the cap IS the duration,
        // however many rounds the athlete actually gets through.
        if let cap = cappedSeconds(for: block) {
            tally.sawExactTimed = true
            var result = BlockDuration()
            result.totalSec = cap
            result.activeSec = cap
            result.isEstimate = false
            // Attribute the cap evenly so per-exercise rows still show something honest.
            let share = block.exercises.isEmpty ? 0 : cap / block.exercises.count
            result.perExercise = block.exercises.map {
                WorkoutDurationComponent(id: $0.id, seconds: share, isEstimate: false)
            }
            return result
        }

        // A superset rests after the pair, not after every exercise.
        let restIsGroupWide = block.structure == .superset

        var roundWork = 0
        var roundRest = 0
        var roundIsEstimate = false
        var groupRestPerRound = 0
        var perExercise: [WorkoutDurationComponent] = []

        for exercise in block.exercises {
            let step = exerciseDuration(exercise, paceTable: paceTable, tally: &tally)
            roundWork += step.workSec
            if step.isEstimate { roundIsEstimate = true }

            if restIsGroupWide {
                groupRestPerRound = max(groupRestPerRound, step.restSec)
            } else {
                roundRest += step.restSec
            }
            if step.restIsEstimate { roundIsEstimate = true }

            perExercise.append(
                WorkoutDurationComponent(
                    id: exercise.id,
                    seconds: (step.workSec + (restIsGroupWide ? 0 : step.restSec)) * rounds,
                    isEstimate: step.isEstimate || step.restIsEstimate
                )
            )
        }
        roundRest += groupRestPerRound

        let work = roundWork * rounds
        var rest = roundRest * rounds

        // Rest BETWEEN rounds — trailing rest after the last round isn't time spent.
        if let between = block.restBetweenSeconds, between > 0, rounds > 1 {
            rest += between * (rounds - 1)
        }

        var total = work + rest

        // Transition padding is itself a guess, so it may only be added to a
        // block that is already estimated. An all-timed circuit stays exact —
        // that's what makes E2 (8 × 4 × 3:00) read 96 MIN and not 96-and-change.
        // Padding is transition time, not work, so it lands outside ACTIVE.
        if roundIsEstimate, rounds > 1, block.exercises.count > 1 {
            total = Int((Double(total) * transitionFactor).rounded())
            tally.sawTransitions = true
        }

        var result = BlockDuration()
        result.totalSec = total
        result.activeSec = work
        result.isEstimate = roundIsEstimate
        result.perExercise = perExercise
        return result
    }

    /// EMOM / AMRAP / Tabata caps — exact wall-clock regardless of content.
    private static func cappedSeconds(for block: Block) -> Int? {
        let rounds = max(1, block.rounds)
        switch block.structure {
        case .emom:
            // "EMOM 24" in the label wins; otherwise one minute per round.
            if let minutes = minutesInLabel(block.label) { return minutes * 60 }
            return rounds * 60
        case .amrap:
            if let minutes = minutesInLabel(block.label) { return minutes * 60 }
            // An AMRAP whose cap is carried on a single timed step.
            if block.exercises.count == 1, let seconds = block.exercises[0].durationSeconds {
                return seconds * rounds
            }
            return nil
        case .tabata:
            // Classic 20s on / 10s off unless the steps say otherwise.
            if block.exercises.allSatisfy({ $0.durationSeconds == nil }) {
                return rounds * block.exercises.count * 30
            }
            return nil
        case .straight, .superset, .circuit, .timedCircuit:
            return nil
        }
    }

    private static func minutesInLabel(_ label: String?) -> Int? {
        guard let label else { return nil }
        let pattern = #"(?:emom|amrap|for time|cap)\D{0,4}(\d{1,3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        guard let match = regex.firstMatch(in: label, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: label),
              let minutes = Int(label[valueRange]),
              minutes > 0 else {
            return nil
        }
        return minutes
    }

    // MARK: - Exercises

    private struct StepDuration {
        var workSec = 0
        var restSec = 0
        var isEstimate = false
        var restIsEstimate = false
    }

    private static func exerciseDuration(
        _ exercise: Exercise,
        paceTable: WorkoutPaceTable,
        tally: inout BasisTally
    ) -> StepDuration {
        var step = StepDuration()
        let sets = max(1, exercise.sets ?? 1)

        if let seconds = exercise.durationSeconds, seconds > 0 {
            step.workSec = seconds * sets
            tally.sawExactTimed = true
        } else if let metres = exercise.distance, metres > 0 {
            let kind = WorkoutSportHonesty.machineKindKey(forName: exercise.name)
            let perMetre = paceTable.secondsPerMetre(forMachineKind: kind ?? runKindIfRunning(exercise.name))
            step.workSec = Int((metres * perMetre).rounded()) * sets
            step.isEstimate = true
            tally.sawDistance = true
        } else if let reps = repCount(from: exercise.reps) {
            step.workSec = sets * (reps * secondsPerRep + setupSecondsPerSet)
            step.isEstimate = true
            tally.sawReps = true
            applyStrengthRest(&step, exercise: exercise, sets: sets, reps: reps, tally: &tally)
            return step
        } else {
            // Open goal, no target — excluded rather than given a fake minute.
            tally.hasOpenSteps = true
            return step
        }

        // Timed / distance steps only rest when the step explicitly says so.
        if let rest = exercise.restSeconds, rest > 0 {
            step.restSec = rest * sets
            tally.sawExplicitRest(rest)
        }
        return step
    }

    private static func applyStrengthRest(
        _ step: inout StepDuration,
        exercise: Exercise,
        sets: Int,
        reps: Int,
        tally: inout BasisTally
    ) {
        if let rest = exercise.restSeconds, rest > 0 {
            step.restSec = rest * sets
            tally.sawExplicitRest(rest)
            return
        }
        let defaultRest = reps <= heavyRepsThreshold ? heavyRestSeconds : defaultRestSeconds
        step.restSec = defaultRest * sets
        step.restIsEstimate = true
        tally.sawDefaultRest(defaultRest)
    }

    /// A distance step on a non-machine movement is a run unless we can tell otherwise.
    private static func runKindIfRunning(_ name: String) -> String? {
        WorkoutSportHonesty.modality(forName: name) == .run ? "run" : nil
    }

    /// Plain reps, or the midpoint of a range. Non-numeric prescriptions
    /// ("max", "AMRAP") are open goals, not zero.
    static func repCount(from raw: String?) -> Int? {
        let split = RepsRange.splitPrescription(raw)
        if let reps = split.reps { return reps }
        if let range = split.range { return (range.low + range.high) / 2 }
        return nil
    }

    // MARK: - Basis copy

    private struct BasisTally {
        var sawExactTimed = false
        var sawDistance = false
        var sawReps = false
        var sawTransitions = false
        var hasOpenSteps = false
        var restDefaults: Set<Int> = []
        var explicitRests: Set<Int> = []

        var hasEstimate: Bool { sawDistance || sawReps || !restDefaults.isEmpty }

        mutating func sawExplicitRest(_ seconds: Int) { explicitRests.insert(seconds) }
        mutating func sawDefaultRest(_ seconds: Int) { restDefaults.insert(seconds) }

        func basisNote(paceTable: WorkoutPaceTable) -> String {
            var note: String
            if sawDistance {
                note = paceTable.isPersonalised
                    ? "ESTIMATED FROM DISTANCES AT YOUR RECENT PACES"
                    : "ESTIMATED FROM DISTANCES AT DEFAULT PACES"
                if sawReps {
                    note += " · REPS AT \(secondsPerRep)S EACH"
                }
            } else if sawReps {
                note = "≈ SETS × (REPS × \(secondsPerRep)S + SETUP) + \(restPhrase)"
            } else if sawExactTimed {
                note = "ALL STEPS TIMED · EXACT"
            } else {
                note = "NO TIMED OR MEASURED STEPS"
            }
            if sawTransitions {
                note += " · + 5% TRANSITIONS"
            }
            if hasOpenSteps {
                note += " · + OPEN STEPS"
            }
            return note
        }

        /// ACTIVE-cell sublabel: names the dominant assumption in three words.
        var activeNote: String {
            if !hasEstimate {
                return hasOpenSteps ? "TIMED · + OPEN STEPS" : "ALL TIMED · EXACT"
            }
            if sawDistance {
                return "WORK · PACES: DEFAULT"
            }
            if sawReps {
                return "LIFTING · \(restPhrase.replacingOccurrences(of: "/SET", with: ""))"
            }
            return "WORK · ESTIMATED"
        }

        /// `REST 60S/SET`, `REST 90S/SET`, or `REST 60–90S/SET` when mixed.
        private var restPhrase: String {
            let rests = restDefaults.union(explicitRests).sorted()
            guard let low = rests.first, let high = rests.last else { return "NO REST" }
            if low == high { return "REST \(low)S/SET" }
            return "REST \(low)–\(high)S/SET"
        }
    }
}

// MARK: - Formatting

extension WorkoutDurationEstimate {
    /// `48 MIN` when exact, `≈ 62 MIN` when estimated. Never `~1 MIN`: a
    /// workout with no measurable steps says so instead of inventing a minute.
    var pillLabel: String { Self.label(seconds: totalSec, isEstimate: isEstimate) }

    var totalLabel: String { Self.label(seconds: totalSec, isEstimate: isEstimate) }

    /// ACTIVE never carries the ≈ prefix — the sublabel names the assumption.
    var activeLabel: String { Self.label(seconds: activeSec, isEstimate: false) }

    var totalSublabel: String { isEstimate ? "TOTAL · ESTIMATED" : "TOTAL" }

    /// True when there is nothing honest to show (no timed, measured or
    /// countable step anywhere).
    var isUnknown: Bool { totalSec <= 0 }

    static func label(seconds: Int, isEstimate: Bool) -> String {
        guard seconds > 0 else { return "TIME NOT SET" }
        let prefix = isEstimate ? "≈ " : ""
        if seconds < 60 {
            return "\(prefix)\(seconds) SEC"
        }
        // Minutes all the way up — a 96-minute circuit reads "96 MIN", matching
        // how the workout was written ("8 × 4 × 3:00"), not "1H 36M".
        let minutes = Int((Double(seconds) / 60.0).rounded())
        return "\(prefix)\(minutes) MIN"
    }
}

extension WorkoutDurationComponent {
    var label: String { WorkoutDurationEstimate.label(seconds: seconds, isEstimate: isEstimate) }
}
