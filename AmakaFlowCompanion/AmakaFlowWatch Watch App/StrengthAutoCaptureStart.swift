//
//  StrengthAutoCaptureStart.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — resolve Watch Start target: plan-linked workout or freeform.
//

import Foundation

enum StrengthAutoCaptureStart {
    /// Matched library / WC workout for a planned DayState strength session.
    static func planLinkedWorkout(
        for session: PlannedSession,
        in workouts: [Workout],
        flagEnabled: Bool
    ) -> Workout? {
        guard flagEnabled else { return nil }
        guard !session.isCompleted else { return nil }
        guard HKWorkoutActivityMapping.isStrengthSportLabel(session.sport) else { return nil }

        if let byID = workouts.first(where: { $0.id == session.id }),
           byID.sport == .strength,
           !byID.intervals.isEmpty {
            return byID
        }

        let normalizedName = session.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let matches = workouts.filter {
            $0.sport == .strength
                && !$0.intervals.isEmpty
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == normalizedName
        }
        // Ambiguous duplicates must not silently pick an arbitrary plan target.
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}
