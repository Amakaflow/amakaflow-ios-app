//
//  FlattenedInterval.swift
//  AmakaFlow
//
//  Helper for flattening nested workout intervals into a linear sequence
//

import Foundation

// MARK: - Flattened Interval
struct FlattenedInterval: Identifiable {
    let id = UUID()
    let interval: WorkoutInterval
    let index: Int
    let label: String
    let details: String
    let roundInfo: String?
    let timerSeconds: Int?
    let stepType: StepType
    let followAlongUrl: String?

    var formattedTime: String? {
        guard let seconds = timerSeconds else { return nil }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return "\(secs)s"
        }
    }
}

// MARK: - Interval Flattening
func flattenIntervals(_ intervals: [WorkoutInterval]) -> [FlattenedInterval] {
    var result: [FlattenedInterval] = []
    var counter = 0

    func flatten(_ items: [WorkoutInterval], roundContext: String? = nil) {
        for interval in items {
            switch interval {
            case .repeat(let reps, let subIntervals):
                for i in 1...reps {
                    flatten(subIntervals, roundContext: "Round \(i)/\(reps)")
                }
            default:
                counter += 1
                result.append(FlattenedInterval(
                    interval: interval,
                    index: counter,
                    label: intervalLabel(interval),
                    details: intervalDetails(interval),
                    roundInfo: roundContext,
                    timerSeconds: intervalTimer(interval),
                    stepType: intervalStepType(interval),
                    followAlongUrl: intervalFollowAlongUrl(interval)
                ))
            }
        }
    }

    flatten(intervals)
    return result
}

// MARK: - Helper Functions

private func intervalLabel(_ interval: WorkoutInterval) -> String {
    switch interval {
    case .warmup:
        return "Warm Up"
    case .cooldown:
        return "Cool Down"
    case .time(_, let target):
        return target ?? "Work"
    case .reps(_, let name, _, _, _):
        return name
    case .distance(let meters, let target):
        return target ?? "\(WorkoutHelpers.formatDistance(meters: meters))"
    case .repeat:
        return "Repeat"
    }
}

private func intervalDetails(_ interval: WorkoutInterval) -> String {
    switch interval {
    case .warmup(let seconds, let target):
        let timeStr = formatSeconds(seconds)
        return target.map { "\(timeStr) - \($0)" } ?? timeStr

    case .cooldown(let seconds, let target):
        let timeStr = formatSeconds(seconds)
        return target.map { "\(timeStr) - \($0)" } ?? timeStr

    case .time(let seconds, let target):
        let timeStr = formatSeconds(seconds)
        return target.map { "\(timeStr) - \($0)" } ?? timeStr

    case .reps(let reps, _, let load, let restSec, _):
        var parts: [String] = ["\(reps) reps"]
        if let load = load {
            parts.append(load)
        }
        if let rest = restSec {
            parts.append("\(rest)s rest")
        }
        return parts.joined(separator: " | ")

    case .distance(let meters, let target):
        let distStr = WorkoutHelpers.formatDistance(meters: meters)
        return target.map { "\(distStr) - \($0)" } ?? distStr

    case .repeat(let reps, _):
        return "\(reps)x"
    }
}

private func intervalTimer(_ interval: WorkoutInterval) -> Int? {
    switch interval {
    case .warmup(let seconds, _),
         .cooldown(let seconds, _),
         .time(let seconds, _):
        return seconds
    case .reps(_, _, _, let restSec, _):
        // Reps intervals might have rest timer
        return restSec
    case .distance, .repeat:
        return nil
    }
}

private func intervalStepType(_ interval: WorkoutInterval) -> StepType {
    switch interval {
    case .warmup, .cooldown, .time:
        return .timed
    case .reps:
        return .reps
    case .distance:
        return .distance
    case .repeat:
        return .timed
    }
}

private func intervalFollowAlongUrl(_ interval: WorkoutInterval) -> String? {
    switch interval {
    case .reps(_, _, _, _, let followAlongUrl):
        return followAlongUrl
    default:
        return nil
    }
}

private func formatSeconds(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let secs = seconds % 60
    if minutes > 0 && secs > 0 {
        return "\(minutes)m \(secs)s"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "\(secs)s"
    }
}
