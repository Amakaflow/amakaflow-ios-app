//
//  StrengthBackfill.swift
//  AmakaFlow
//
//  AMA-2290: Pure draft model for post-stop strength set/reps/weight backfill.
//  Manual entry is first-class; AI suggestions are never required to save.
//

import Foundation

/// One editable set row in the post-session strength backfill editor.
struct StrengthBackfillSetDraft: Identifiable, Equatable, Hashable {
    let id: String
    var setNumber: Int
    var reps: Int?
    var weight: Double?
    var unit: String
    var completed: Bool

    init(
        id: String = UUID().uuidString,
        setNumber: Int,
        reps: Int? = nil,
        weight: Double? = nil,
        unit: String = "lbs",
        completed: Bool = true
    ) {
        self.id = id
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.unit = unit
        self.completed = completed
    }
}

/// One exercise block of editable sets.
struct StrengthBackfillExerciseDraft: Identifiable, Equatable, Hashable {
    let id: String
    var exerciseIndex: Int
    var exerciseName: String
    var sets: [StrengthBackfillSetDraft]

    init(
        id: String = UUID().uuidString,
        exerciseIndex: Int,
        exerciseName: String,
        sets: [StrengthBackfillSetDraft]
    ) {
        self.id = id
        self.exerciseIndex = exerciseIndex
        self.exerciseName = exerciseName
        self.sets = sets
    }
}

/// Pure helpers for seeding / encoding phone strength backfill.
enum StrengthBackfill {
    /// Whether a workout structure has any reps-based strength work worth backfilling.
    static func shouldOfferBackfill(intervals: [WorkoutInterval]?) -> Bool {
        guard let intervals, !intervals.isEmpty else { return false }
        return flattenRepsExercises(intervals).isEmpty == false
    }

    /// Watch is never required for phone strength record + backfill.
    static var requiresAppleWatch: Bool { false }

    /// AI weight suggestions must never gatekeep save.
    static var requiresAISuggestions: Bool { false }

    /// Build editable drafts from planned structure, overlaying any live set logs.
    static func draft(
        from intervals: [WorkoutInterval]?,
        existingSetLogs: [SetLog]? = nil
    ) -> [StrengthBackfillExerciseDraft] {
        let planned = flattenRepsExercises(intervals ?? [])
        guard !planned.isEmpty else {
            // No structure — allow a single blank exercise for freeform manual entry.
            return [
                StrengthBackfillExerciseDraft(
                    exerciseIndex: 0,
                    exerciseName: "Exercise 1",
                    sets: [StrengthBackfillSetDraft(setNumber: 1, reps: nil, weight: nil)]
                )
            ]
        }

        let logsByName = Dictionary(
            uniqueKeysWithValues: (existingSetLogs ?? []).map { ($0.exerciseName.lowercased(), $0) }
        )

        return planned.enumerated().map { index, exercise in
            let log = logsByName[exercise.name.lowercased()]
            let setCount = max(exercise.sets, log?.sets.count ?? 0, 1)
            let sets: [StrengthBackfillSetDraft] = (1...setCount).map { setNumber in
                let logged = log?.sets.first(where: { $0.setNumber == setNumber })
                return StrengthBackfillSetDraft(
                    setNumber: setNumber,
                    reps: exercise.reps,
                    weight: logged?.weight,
                    unit: logged?.unit ?? "lbs",
                    completed: logged?.completed ?? true
                )
            }
            return StrengthBackfillExerciseDraft(
                exerciseIndex: log?.exerciseIndex ?? index,
                exerciseName: exercise.name,
                sets: sets
            )
        }
    }

    /// Encode drafts to API `set_logs` shape. Empty weights are allowed (manual save without AI).
    static func setLogs(from drafts: [StrengthBackfillExerciseDraft]) -> [SetLog] {
        drafts.map { exercise in
            SetLog(
                exerciseName: exercise.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Exercise \(exercise.exerciseIndex + 1)"
                    : exercise.exerciseName,
                exerciseIndex: exercise.exerciseIndex,
                sets: exercise.sets.map { set in
                    SetEntry(
                        setNumber: set.setNumber,
                        weight: set.weight,
                        unit: set.weight == nil ? nil : set.unit,
                        completed: set.completed
                    )
                }
            )
        }
    }

    /// Round-trip: drafts → set_logs → drafts preserve weights/units (ignoring generated ids).
    static func roundTripPreservesWeights(_ drafts: [StrengthBackfillExerciseDraft]) -> Bool {
        let encoded = setLogs(from: drafts)
        let rebuilt = draft(
            from: drafts.map { exercise in
                .reps(
                    sets: exercise.sets.count,
                    reps: exercise.sets.first?.reps ?? 0,
                    name: exercise.exerciseName,
                    load: nil,
                    restSec: nil,
                    followAlongUrl: nil
                )
            },
            existingSetLogs: encoded
        )
        guard rebuilt.count == drafts.count else { return false }
        for (lhs, rhs) in zip(drafts, rebuilt) {
            guard lhs.exerciseName == rhs.exerciseName else { return false }
            guard lhs.sets.count == rhs.sets.count else { return false }
            for (ls, rs) in zip(lhs.sets, rhs.sets) {
                guard ls.setNumber == rs.setNumber else { return false }
                guard ls.weight == rs.weight else { return false }
                if ls.weight != nil {
                    guard ls.unit == rs.unit else { return false }
                }
            }
        }
        return true
    }

    // MARK: - Private

    private struct PlannedReps {
        let name: String
        let sets: Int
        let reps: Int
    }

    private static func flattenRepsExercises(_ intervals: [WorkoutInterval]) -> [PlannedReps] {
        var result: [PlannedReps] = []
        for interval in intervals {
            switch interval {
            case .reps(let sets, let reps, let name, _, _, _):
                result.append(PlannedReps(name: name, sets: max(sets ?? 1, 1), reps: reps))
            case .repeat(let times, let children):
                let nested = flattenRepsExercises(children)
                for _ in 0..<max(times, 1) {
                    result.append(contentsOf: nested)
                }
            default:
                continue
            }
        }
        // Collapse consecutive identical names (expanded set steps → one exercise).
        var collapsed: [PlannedReps] = []
        for item in result {
            if let last = collapsed.last, last.name.caseInsensitiveCompare(item.name) == .orderedSame {
                collapsed[collapsed.count - 1] = PlannedReps(
                    name: last.name,
                    sets: last.sets + item.sets,
                    reps: item.reps > 0 ? item.reps : last.reps
                )
            } else {
                collapsed.append(item)
            }
        }
        return collapsed
    }
}
