//
//  FreeformStrengthWorkout.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — open strength recording without a DayState / Fitness plan.
//  AMA-2428 — starts as Strength; athlete may reclassify after End on passive UI.
//

import Foundation

enum FreeformStrengthWorkout {
    static let idPrefix = "ama-2420-freeform-strength"
    /// Open set slots for a typical gym session; user can End early.
    static let openSetCapacity = 24

    static func make(
        now: Date = Date(),
        uniqueSuffix: String = UUID().uuidString
    ) -> Workout {
        Workout(
            id: "\(idPrefix)-\(Int(now.timeIntervalSince1970))-\(uniqueSuffix)",
            name: "Strength",
            sport: .strength,
            duration: 0,
            intervals: [
                .reps(
                    sets: openSetCapacity,
                    reps: 10,
                    name: "Exercise",
                    load: nil,
                    restSec: nil,
                    followAlongUrl: nil
                )
            ],
            description: "Open strength recording",
            source: .other
        )
    }

    static func isFreeformID(_ id: String) -> Bool {
        id.hasPrefix(idPrefix)
    }
}
