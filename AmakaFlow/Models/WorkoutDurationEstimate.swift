//
//  WorkoutDurationEstimate.swift
//  AmakaFlow
//
//  AMA-2395 — the estimator's value types and their display formatting, split
//  out of WorkoutDurationEstimator.swift to keep both files readable.
//
//  `WorkoutDurationEstimate.label` is where "~1 MIN" is made unrepresentable:
//  there is no code path that emits a tilde, and zero seconds says so.
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
