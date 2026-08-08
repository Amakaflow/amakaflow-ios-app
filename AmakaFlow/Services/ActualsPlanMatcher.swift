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
        let scored: [(ActualsPlanCandidate, Double, String)] = candidates.map { candidate in
            let signals = scoreSignals(activity: activity, candidate: candidate)
            let total =
                signals.time * wTime
                + signals.duration * wDuration
                + signals.distance * wDistance
                + signals.type * wType
                + signals.hr * wHR
            let why = whyLine(from: signals)
            return (candidate, total, why)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.id < rhs.0.id
        }

        let top = Array(scored.prefix(max(0, limit)))
        return top.enumerated().map { index, row in
            ActualsPlanMatch(
                candidate: row.0,
                score: row.1,
                whyLine: row.2,
                isBest: index == 0 && row.1 > 0
            )
        }
    }

    // MARK: - Signals (testable)

    struct Signals: Equatable {
        var time: Double
        var duration: Double
        var distance: Double
        var type: Double
        var hr: Double
        /// Fragments used to build the WHY line (already uppercase).
        var whyFragments: [String]
    }

    static func scoreSignals(
        activity: ActualsUnmappedActivity,
        candidate: ActualsPlanCandidate
    ) -> Signals {
        var fragments: [String] = []

        // Scheduled-time proximity
        let timeScore: Double
        if let scheduled = candidate.scheduledStart {
            let delta = abs(activity.startDate.timeIntervalSince(scheduled))
            if delta <= 3 * 60 {
                timeScore = 1
                fragments.append("SAME START")
            } else if delta <= 30 * 60 {
                timeScore = max(0, 1 - (delta - 3 * 60) / (27 * 60))
                fragments.append("CLOSE START")
            } else if Calendar.current.isDate(activity.startDate, inSameDayAs: scheduled) {
                timeScore = 0.25
                fragments.append("SAME DAY")
            } else {
                timeScore = 0
            }
        } else {
            timeScore = 0.15 // library item with no schedule — mild prior
        }

        // Duration
        let durationScore: Double
        if let planned = candidate.durationSeconds, planned > 0, activity.durationSeconds > 0 {
            let ratio = abs(activity.durationSeconds - planned) / max(activity.durationSeconds, planned)
            if ratio <= 0.08 {
                durationScore = 1
                fragments.append("SAME DURATION")
            } else if ratio <= 0.25 {
                durationScore = 1 - (ratio - 0.08) / 0.17
                fragments.append("DURATION FITS")
            } else {
                durationScore = 0
            }
        } else {
            durationScore = 0.2
        }

        // Distance
        let distanceScore: Double
        if let aDist = activity.distanceMeters, let pDist = candidate.distanceMeters,
           aDist > 0, pDist > 0 {
            let ratio = abs(aDist - pDist) / max(aDist, pDist)
            if ratio <= 0.08 {
                distanceScore = 1
                fragments.append("SAME DISTANCE")
            } else if ratio <= 0.25 {
                distanceScore = 1 - (ratio - 0.08) / 0.17
                fragments.append("DISTANCE FITS")
            } else {
                distanceScore = 0
            }
        } else {
            distanceScore = 0.2
        }

        // Type
        let typeScore: Double
        if activity.type == candidate.type {
            typeScore = 1
            if activity.type != .other { fragments.append("SAME TYPE") }
        } else if activity.type == .other || candidate.type == .other {
            typeScore = 0.4
        } else {
            typeScore = 0
        }

        // HR shape
        let hrScore: Double
        if let avg = activity.avgHR, let target = candidate.targetAvgHR, target > 0 {
            let ratio = abs(avg - target) / target
            if ratio <= 0.08 {
                hrScore = 1
                fragments.append("HR FITS")
            } else if ratio <= 0.18 {
                hrScore = 0.6
                // Activity hotter than plan → "HR SAYS TEMPO"
                if avg > target {
                    fragments.append("HR SAYS TEMPO")
                } else {
                    fragments.append("HR SOFTER")
                }
            } else {
                hrScore = 0.15
                if avg > target { fragments.append("HR SAYS TEMPO") }
            }
        } else {
            hrScore = 0.2
        }

        return Signals(
            time: timeScore,
            duration: durationScore,
            distance: distanceScore,
            type: typeScore,
            hr: hrScore,
            whyFragments: fragments
        )
    }

    /// Build locked-style WHY: top fragments joined with " · ", max 2.
    static func whyLine(from signals: Signals) -> String {
        let parts = Array(signals.whyFragments.prefix(2))
        if parts.isEmpty { return "POSSIBLE MATCH" }
        return parts.joined(separator: " · ")
    }
}
