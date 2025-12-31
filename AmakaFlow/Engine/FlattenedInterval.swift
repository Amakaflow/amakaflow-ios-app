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
    let targetReps: Int?
    let setNumber: Int?      // Current set number (1-based)
    let totalSets: Int?      // Total number of sets
    let hasRestAfter: Bool   // Whether this step has a rest period after it
    let restAfterSeconds: Int?  // Rest duration: nil = manual (tap when ready), 0 = no rest, >0 = timed countdown

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

    /// Formatted rest duration for display
    var formattedRestTime: String? {
        guard let seconds = restAfterSeconds, seconds > 0 else { return nil }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return "\(secs)s"
        }
    }

    /// Display label including set info if applicable
    var displayLabel: String {
        if let setNum = setNumber, let total = totalSets, total > 1 {
            return "\(label) - Set \(setNum) of \(total)"
        }
        return label
    }
}

// MARK: - Interval Flattening
func flattenIntervals(_ intervals: [WorkoutInterval]) -> [FlattenedInterval] {
    var result: [FlattenedInterval] = []
    var counter = 0

    print("📱 flattenIntervals: Processing \(intervals.count) intervals")

    func flatten(_ items: [WorkoutInterval], roundContext: String? = nil, overrideRestSec: Int?? = nil) {
        for interval in items {
            switch interval {
            case .repeat(let repeatCount, let subIntervals):
                print("📱 Processing repeat: \(repeatCount)x with \(subIntervals.count) sub-intervals")

                // Check if this is a "sets-style" repeat (single reps interval inside)
                // In this case, we treat each iteration as a set
                let isSetsStyleRepeat = subIntervals.count == 1 && {
                    if case .reps = subIntervals[0] { return true }
                    return false
                }()

                if isSetsStyleRepeat, case .reps(_, let reps, let name, let load, let restSec, let followAlongUrl) = subIntervals[0] {
                    // Handle sets-style repeat directly - create exercise steps with rest info
                    for i in 1...repeatCount {
                        counter += 1

                        // All sets have rest after them (for transition between sets or to next exercise)
                        // restSec: nil = manual, 0 = no rest, >0 = timed
                        let hasRest = restSec != 0  // Has rest unless explicitly 0

                        result.append(FlattenedInterval(
                            interval: subIntervals[0],
                            index: counter,
                            label: name,
                            details: intervalDetailsForSet(reps: reps, load: load, setNum: i, totalSets: repeatCount),
                            roundInfo: "Set \(i) of \(repeatCount)",
                            timerSeconds: nil, // Reps are not timed
                            stepType: .reps,
                            followAlongUrl: followAlongUrl,
                            targetReps: reps,
                            setNumber: i,
                            totalSets: repeatCount,
                            hasRestAfter: hasRest,
                            restAfterSeconds: restSec
                        ))
                    }
                } else {
                    // Regular repeat - process sub-intervals for each round
                    for i in 1...repeatCount {
                        let roundContext = "Round \(i) of \(repeatCount)"
                        flatten(subIntervals, roundContext: roundContext)
                    }
                }

            case .reps(let sets, let reps, let name, let load, let restSec, let followAlongUrl):
                print("📱 Processing reps: \(name), sets=\(sets ?? -1), reps=\(reps), restSec=\(restSec ?? -999)")
                let totalSets = sets ?? 1

                for setNum in 1...totalSets {
                    counter += 1

                    // Has rest after all sets except the last one (within a direct .reps block)
                    // restSec: nil = manual, 0 = no rest, >0 = timed
                    let hasRest = setNum < totalSets && restSec != 0

                    result.append(FlattenedInterval(
                        interval: interval,
                        index: counter,
                        label: name,
                        details: intervalDetailsForSet(reps: reps, load: load, setNum: setNum, totalSets: totalSets),
                        roundInfo: roundContext,
                        timerSeconds: nil, // Reps are not timed
                        stepType: .reps,
                        followAlongUrl: followAlongUrl,
                        targetReps: reps,
                        setNumber: setNum,
                        totalSets: totalSets,
                        hasRestAfter: hasRest,
                        restAfterSeconds: hasRest ? restSec : nil
                    ))
                }

            default:
                counter += 1
                // Cooldown shouldn't have rest after (it ends the workout)
                // All other steps (warmup, time, distance) get manual rest after
                let isCooldown: Bool = {
                    if case .cooldown = interval { return true }
                    return false
                }()

                result.append(FlattenedInterval(
                    interval: interval,
                    index: counter,
                    label: intervalLabel(interval),
                    details: intervalDetails(interval),
                    roundInfo: roundContext,
                    timerSeconds: intervalTimer(interval),
                    stepType: intervalStepType(interval),
                    followAlongUrl: intervalFollowAlongUrl(interval),
                    targetReps: intervalTargetReps(interval),
                    setNumber: nil,
                    totalSets: nil,
                    hasRestAfter: !isCooldown,  // All steps except cooldown have rest
                    restAfterSeconds: isCooldown ? nil : nil  // nil = manual rest ("tap when ready")
                ))
            }
        }
    }

    flatten(intervals)
    print("📱 flattenIntervals: Created \(result.count) flattened steps")
    for (i, step) in result.enumerated() {
        print("📱   Step \(i+1): \(step.label), hasRest=\(step.hasRestAfter), restSec=\(step.restAfterSeconds ?? -1), set=\(step.setNumber ?? 0)/\(step.totalSets ?? 0)")
    }
    return result
}

/// Helper to create details string for a specific set
private func intervalDetailsForSet(reps: Int, load: String?, setNum: Int, totalSets: Int) -> String {
    var parts: [String] = ["\(reps) reps"]
    if let load = load {
        parts.append(load)
    }
    if totalSets > 1 {
        parts.append("Set \(setNum)/\(totalSets)")
    }
    return parts.joined(separator: " | ")
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
    case .reps(_, _, let name, _, _, _):
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

    case .reps(let sets, let reps, _, let load, let restSec, _):
        var parts: [String] = []
        if let sets = sets, sets > 1 {
            parts.append("\(sets) sets x \(reps) reps")
        } else {
            parts.append("\(reps) reps")
        }
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
    case .reps(_, _, _, _, let restSec, _):
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
    case .reps(_, _, _, _, _, let followAlongUrl):
        return followAlongUrl
    default:
        return nil
    }
}

private func intervalTargetReps(_ interval: WorkoutInterval) -> Int? {
    switch interval {
    case .reps(_, let reps, _, _, _, _):
        return reps
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
