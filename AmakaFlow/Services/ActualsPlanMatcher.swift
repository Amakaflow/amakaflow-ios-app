//
//  ActualsPlanMatcher.swift
//  AmakaFlow
//
//  AMA-2387: map unmatched activity → plan candidates with WHY lines.
//  Score: scheduled-time, duration, distance, type, HR shape (ACTUALS.md §7).
//

import Foundation

enum ActualsWorkoutType: String, Equatable, Codable, Hashable {
    case run
    case ride
    case strength
    case other
}

/// A finished activity that is not yet attached to a planned workout.
struct ActualsUnmappedActivity: Equatable, Hashable {
    let title: String
    let provider: ActualsSourceProvider
    let startDate: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double?
    let calories: Double?
    let avgHR: Double?
    let type: ActualsWorkoutType
    /// Raw Strava `type` / `sport_type` for write-back skip rules (e.g. `VirtualRide`).
    var stravaTypeRaw: String? = nil
    /// Pre-write Strava description body used by skipDescribed / append-preserve.
    var activityDescription: String = ""
    var recordingApp: String? = nil
    var isRace: Bool = false

    var endDate: Date {
        startDate.addingTimeInterval(durationSeconds)
    }
}

/// A planned / library workout that could be the map target.
struct ActualsPlanCandidate: Identifiable, Equatable {
    let id: String
    let title: String
    /// Mono source line, e.g. "STRYD · 12:50 TODAY" / "MY WORKOUTS".
    let sourceLabel: String
    let scheduledStart: Date?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let type: ActualsWorkoutType
    /// Target / expected avg HR when known (HR-shape signal).
    let targetAvgHR: Double?
}

struct ActualsPlanMatch: Identifiable, Equatable {
    let candidate: ActualsPlanCandidate
    /// 0...1 aggregate score.
    let score: Double
    /// Uppercase mono WHY, e.g. "SAME START · SAME DISTANCE".
    let whyLine: String
    let isBest: Bool

    var id: String { candidate.id }
}

enum ActualsPlanMatchOutcome: Equatable {
    case mapped(candidateID: String)
    /// Unmapped still counts (keep as is).
    case keepAsIs
}

private struct ActualsPlanMatchScoreRow {
    let candidate: ActualsPlanCandidate
    let score: Double
    let whyLine: String
}

enum ActualsPlanMatcher {
    /// Weighting for the five signals in ACTUALS.md §7.
    private static let wTime: Double = 0.30
    private static let wDuration: Double = 0.20
    private static let wDistance: Double = 0.20
    private static let wType: Double = 0.15
    private static let wHR: Double = 0.15

    /// Rank plan candidates for an unmatched activity. Best first.
    static func rank(
        activity: ActualsUnmappedActivity,
        candidates: [ActualsPlanCandidate],
        limit: Int = 5
    ) -> [ActualsPlanMatch] {
        let scored: [ActualsPlanMatchScoreRow] = candidates.map { candidate in
            let signals = scoreSignals(activity: activity, candidate: candidate)
            let total =
                signals.time * wTime
                + signals.duration * wDuration
                + signals.distance * wDistance
                + signals.type * wType
                + signals.heartRate * wHR
            let why = whyLine(from: signals)
            return ActualsPlanMatchScoreRow(candidate: candidate, score: total, whyLine: why)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.candidate.id < rhs.candidate.id
        }

        let top = Array(scored.prefix(max(0, limit)))
        return top.enumerated().map { index, row in
            ActualsPlanMatch(
                candidate: row.candidate,
                score: row.score,
                whyLine: row.whyLine,
                isBest: index == 0 && row.score > 0
            )
        }
    }

    // MARK: - Signals (testable)

    struct Signals: Equatable {
        var time: Double
        var duration: Double
        var distance: Double
        var type: Double
        var heartRate: Double
        /// Fragments used to build the WHY line (already uppercase).
        var whyFragments: [String]
    }

    static func scoreSignals(
        activity: ActualsUnmappedActivity,
        candidate: ActualsPlanCandidate
    ) -> Signals {
        var fragments: [String] = []
        let timeScore = timeSignal(activity: activity, candidate: candidate, fragments: &fragments)
        let durationScore = durationSignal(activity: activity, candidate: candidate, fragments: &fragments)
        let distanceScore = distanceSignal(activity: activity, candidate: candidate, fragments: &fragments)
        let typeScore = typeSignal(activity: activity, candidate: candidate, fragments: &fragments)
        let heartRateScore = heartRateSignal(activity: activity, candidate: candidate, fragments: &fragments)

        return Signals(
            time: timeScore,
            duration: durationScore,
            distance: distanceScore,
            type: typeScore,
            heartRate: heartRateScore,
            whyFragments: fragments
        )
    }

    /// Build locked-style WHY: top fragments joined with " · ", max 2.
    static func whyLine(from signals: Signals) -> String {
        let parts = Array(signals.whyFragments.prefix(2))
        if parts.isEmpty { return "POSSIBLE MATCH" }
        return parts.joined(separator: " · ")
    }

    // MARK: - Signal helpers

    private static func timeSignal(
        activity: ActualsUnmappedActivity,
        candidate: ActualsPlanCandidate,
        fragments: inout [String]
    ) -> Double {
        guard let scheduled = candidate.scheduledStart else {
            return 0.15 // library item with no schedule — mild prior
        }

        let delta = abs(activity.startDate.timeIntervalSince(scheduled))
        if delta <= 3 * 60 {
            fragments.append("SAME START")
            return 1
        }
        if delta <= 30 * 60 {
            fragments.append("CLOSE START")
            return max(0, 1 - (delta - 3 * 60) / (27 * 60))
        }
        if Calendar.current.isDate(activity.startDate, inSameDayAs: scheduled) {
            fragments.append("SAME DAY")
            return 0.25
        }
        return 0
    }

    private static func durationSignal(
        activity: ActualsUnmappedActivity,
        candidate: ActualsPlanCandidate,
        fragments: inout [String]
    ) -> Double {
        guard let planned = candidate.durationSeconds, planned > 0, activity.durationSeconds > 0 else {
            return 0.2
        }

        let ratio = abs(activity.durationSeconds - planned) / max(activity.durationSeconds, planned)
        if ratio <= 0.08 {
            fragments.append("SAME DURATION")
            return 1
        }
        if ratio <= 0.25 {
            fragments.append("DURATION FITS")
            return 1 - (ratio - 0.08) / 0.17
        }
        return 0
    }

    private static func distanceSignal(
        activity: ActualsUnmappedActivity,
        candidate: ActualsPlanCandidate,
        fragments: inout [String]
    ) -> Double {
        guard let activityDistance = activity.distanceMeters,
              let plannedDistance = candidate.distanceMeters,
              activityDistance > 0,
              plannedDistance > 0 else {
            return 0.2
        }

        let ratio = abs(activityDistance - plannedDistance) / max(activityDistance, plannedDistance)
        if ratio <= 0.08 {
            fragments.append("SAME DISTANCE")
            return 1
        }
        if ratio <= 0.25 {
            fragments.append("DISTANCE FITS")
            return 1 - (ratio - 0.08) / 0.17
        }
        return 0
    }

    private static func typeSignal(
        activity: ActualsUnmappedActivity,
        candidate: ActualsPlanCandidate,
        fragments: inout [String]
    ) -> Double {
        if activity.type == candidate.type {
            if activity.type != .other { fragments.append("SAME TYPE") }
            return 1
        }
        if activity.type == .other || candidate.type == .other {
            return 0.4
        }
        return 0
    }

    private static func heartRateSignal(
        activity: ActualsUnmappedActivity,
        candidate: ActualsPlanCandidate,
        fragments: inout [String]
    ) -> Double {
        guard let avg = activity.avgHR, let target = candidate.targetAvgHR, target > 0 else {
            return 0.2
        }

        let ratio = abs(avg - target) / target
        if ratio <= 0.08 {
            fragments.append("HR FITS")
            return 1
        }
        if ratio <= 0.18 {
            if avg > target {
                fragments.append("HR SAYS TEMPO")
            } else {
                fragments.append("HR SOFTER")
            }
            return 0.6
        }
        if avg > target { fragments.append("HR SAYS TEMPO") }
        return 0.15
    }
}
