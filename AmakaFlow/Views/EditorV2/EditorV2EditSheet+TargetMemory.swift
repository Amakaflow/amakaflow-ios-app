//
//  EditorV2EditSheet+TargetMemory.swift
//  AmakaFlow
//
//  AMA-2312 — session-local focused-editor target state.
//

import Foundation

/// The five mutually exclusive work-target families presented by the focused editor.
enum EditorV2EditTargetKind: String, CaseIterable, Equatable {
    case reps
    case range
    case timed
    case cals
    case open

    var title: String {
        switch self {
        case .reps: return "Reps"
        case .range: return "Range"
        case .timed: return "Timed"
        case .cals: return "Cals"
        case .open: return "Open"
        }
    }

    var accessibilityIdentifier: String {
        "af_exsheet_target_\(rawValue)"
    }
}

private enum EditorV2EditTargetIntent: Equatable {
    case reps(Int)
    case range(min: Int, max: Int)
    case timed(Int)
    case cals(Int)
    case open
}

/// Session-local values for each target family. Switching targets never destroys a
/// value the athlete just entered; an absent family receives its product default.
struct EditorV2EditTargetMemory: Equatable {
    var kind: EditorV2EditTargetKind
    var reps: Int = 10
    var rangeMin: Int = 8
    var rangeMax: Int = 12
    var workSeconds: Int = 40
    var calories: Int = 15
    private let initialIntent: EditorV2EditTargetIntent?
    private var shouldApplyTarget: Bool

    init(exercise: EditorV2Exercise) {
        if exercise.openGoal {
            kind = .open
            initialIntent = .open
        } else if let range = exercise.repsRange {
            kind = .range
            rangeMin = range.low
            rangeMax = range.high
            initialIntent = .range(min: range.low, max: range.high)
        } else if let seconds = exercise.durationSeconds {
            kind = .timed
            workSeconds = seconds
            initialIntent = .timed(seconds)
        } else if let targetCalories = exercise.calories {
            kind = .cals
            calories = targetCalories
            initialIntent = .cals(targetCalories)
        } else {
            kind = .reps
            if let targetReps = exercise.reps {
                reps = targetReps
                initialIntent = .reps(targetReps)
            } else {
                reps = Self.defaultReps
                initialIntent = nil
            }
        }
        shouldApplyTarget = initialIntent != nil
    }

    static let defaultReps = 10
    static let defaultRangeMin = 8
    static let defaultRangeMax = 12
    static let defaultWorkSeconds = 40
    static let defaultCalories = 15

    mutating func setRangeMin(_ value: Int) {
        let updated = Swift.min(Swift.max(1, value), rangeMax)
        guard updated != rangeMin else { return }
        rangeMin = updated
        shouldApplyTarget = true
    }

    mutating func setRangeMax(_ value: Int) {
        let updated = Swift.max(rangeMin, Swift.min(50, value))
        guard updated != rangeMax else { return }
        rangeMax = updated
        shouldApplyTarget = true
    }

    mutating func select(_ targetKind: EditorV2EditTargetKind) {
        guard targetKind != kind else { return }
        kind = targetKind
        shouldApplyTarget = true
    }

    mutating func setReps(_ value: Int) {
        guard value != reps else { return }
        reps = value
        shouldApplyTarget = true
    }

    mutating func setWorkSeconds(_ value: Int) {
        guard value != workSeconds else { return }
        workSeconds = value
        shouldApplyTarget = true
    }

    mutating func setCalories(_ value: Int) {
        guard value != calories else { return }
        calories = value
        shouldApplyTarget = true
    }

    mutating func apply(to exercise: inout EditorV2Exercise) {
        guard shouldApplyTarget else { return }
        let changed = currentIntent != initialIntent
        clearTarget(on: &exercise)
        writeTarget(to: &exercise)
        if changed { exercise.stampUser(provenanceField) }
    }

    private func clearTarget(on exercise: inout EditorV2Exercise) {
        exercise.openGoal = false
        exercise.reps = nil
        exercise.repsRange = nil
        exercise.durationSeconds = nil
        exercise.distanceMeters = nil
        exercise.calories = nil
    }

    private func writeTarget(to exercise: inout EditorV2Exercise) {
        switch kind {
        case .reps:
            exercise.reps = reps
        case .range:
            exercise.repsRange = RepsRange(low: rangeMin, high: rangeMax)
        case .timed:
            exercise.durationSeconds = workSeconds
        case .cals:
            exercise.calories = calories
        case .open:
            exercise.openGoal = true
        }
    }

    private var provenanceField: String {
        switch kind {
        case .reps: return "reps"
        case .range: return "reps_range"
        case .timed: return "duration_seconds"
        case .cals: return "calories"
        case .open: return "open_goal"
        }
    }

    private var currentIntent: EditorV2EditTargetIntent {
        switch kind {
        case .reps: return .reps(reps)
        case .range: return .range(min: rangeMin, max: rangeMax)
        case .timed: return .timed(workSeconds)
        case .cals: return .cals(calories)
        case .open: return .open
        }
    }
}

func editorV2CommitEditDraft(
    _ draft: EditorV2Exercise,
    targetMemory: EditorV2EditTargetMemory
) -> EditorV2Exercise {
    var committed = draft
    var targetMemory = targetMemory
    targetMemory.apply(to: &committed)
    // AMA-2368 — open rest must not serialize with timed seconds.
    if committed.restOpen == true {
        committed.restSeconds = nil
    }
    return committed
}
