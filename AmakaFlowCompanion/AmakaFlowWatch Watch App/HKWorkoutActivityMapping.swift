//
//  HKWorkoutActivityMapping.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — map WorkoutSport → HKWorkoutActivityType (strength uses
//  traditionalStrengthTraining when experimental auto-capture is on).
//

import Foundation
import HealthKit

enum HKWorkoutActivityMapping {
    static func activityType(
        for sport: WorkoutSport,
        strengthAutoCaptureEnabled: Bool = WatchStrengthAutoCaptureSettings.isEnabled
    ) -> HKWorkoutActivityType {
        switch sport {
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .strength:
            return strengthAutoCaptureEnabled
                ? .traditionalStrengthTraining
                : .functionalStrengthTraining
        case .mobility:
            return .yoga
        case .swimming:
            return .swimming
        case .cardio, .mixed:
            return .mixedCardio
        case .conditioning:
            return .highIntensityIntervalTraining
        case .other:
            return .other
        }
    }

    /// Planned DayState sport strings that count as strength for Start affordance.
    static func isStrengthSportLabel(_ sport: String) -> Bool {
        let normalized = sport
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return normalized == "strength"
            || normalized == "traditionalstrengthtraining"
            || normalized == "functionalstrengthtraining"
            || normalized.contains("strength")
    }
}
