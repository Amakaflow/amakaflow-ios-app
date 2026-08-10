//
//  WorkoutDurationEstimate.swift
//  AmakaFlow
//
//  AMA-2395 — value types + display formatting for WorkoutDurationEstimator.
//  The string "~1 MIN" is unrepresentable here.
//

import Foundation

struct WorkoutExerciseDuration: Equatable, Sendable {
    let exerciseId: String
    let seconds: Int
    let isEstimate: Bool
    /// True when the step had no measurable target and was excluded from totals.
    let isOpen: Bool
}

struct WorkoutSectionDuration: Equatable, Sendable {
    let blockId: String
    let seconds: Int
    let isEstimate: Bool
}

struct WorkoutDurationEstimate: Equatable, Sendable {
    let totalSec: Int
    let activeSec: Int
    let isEstimate: Bool
    let perSection: [WorkoutSectionDuration]
    let perExercise: [WorkoutExerciseDuration]
    let basisNote: String
    /// Dominant ACTIVE sublabel, e.g. `ALL TIMED · EXACT` / `LIFTING · REST 60S`.
    let activeSublabel: String

    /// Hero / pill / section minute label. Exact → `48 MIN`; estimated → `≈ 62 MIN`.
    /// Never emits a tilde-prefixed fake minute.
    var minuteLabel: String {
        Self.minuteLabel(seconds: totalSec, isEstimate: isEstimate)
    }

    var activeMinuteLabel: String {
        Self.minuteLabel(seconds: activeSec, isEstimate: false)
    }

    var totalSublabel: String {
        isEstimate ? "TOTAL · ESTIMATED" : "TOTAL"
    }

    static func minuteLabel(seconds: Int, isEstimate: Bool) -> String {
        guard seconds > 0 else { return "TIME NOT SET" }
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        if isEstimate {
            return "≈ \(minutes) MIN"
        }
        return "\(minutes) MIN"
    }

    static func sectionMinuteLabel(seconds: Int, isEstimate: Bool) -> String {
        guard seconds > 0 else { return "" }
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        if isEstimate {
            return "≈ \(minutes) MIN"
        }
        return "\(minutes) MIN"
    }

    /// Compact library meta minutes (`≈ 62 min` / `96 min`), never `~1 min`.
    static func libraryMinutes(seconds: Int, isEstimate: Bool) -> String? {
        guard seconds > 0 else { return nil }
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        if isEstimate {
            return "≈ \(minutes) min"
        }
        return "\(minutes) min"
    }
}
