//
//  AppleStartHandoffOverrides.swift
//  AmakaFlow
//
//  Injection seams for AppleStartHandoffService (saver / schedule-cap).
//

import Foundation
#if canImport(WorkoutKit)
import WorkoutKit
#endif

/// AMA-2330: test seam for the at-cap preflight — avoids linking WorkoutKit in tests.
protocol ScheduleCapReading: Sendable {
    func scheduleCapStatus() async -> (scheduledCount: Int, maxAllowedCount: Int)
}

#if canImport(WorkoutKit)
@available(iOS 18.0, *)
struct LiveScheduleCapReader: ScheduleCapReading {
    func scheduleCapStatus() async -> (scheduledCount: Int, maxAllowedCount: Int) {
        let count = await WorkoutScheduler.shared.scheduledWorkouts.count
        return (count, WorkoutScheduler.maxAllowedScheduledWorkoutCount)
    }
}
#endif

/// How `AppleStartHandoffService` obtains a WorkoutKit saver.
enum WorkoutKitSaverOverride {
    case automatic
    case injected(any WorkoutKitSaving)
    case disabled
}

/// How `AppleStartHandoffService` obtains its at-cap preflight reader.
///
/// Defaults to `.disabled` so existing unit tests do not hit live WorkoutKit.
/// Production call sites opt in with `.automatic`.
enum ScheduleCapReaderOverride {
    case automatic
    case injected(any ScheduleCapReading)
    case disabled
}
