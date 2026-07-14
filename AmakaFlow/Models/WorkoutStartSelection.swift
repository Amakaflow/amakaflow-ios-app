//
//  WorkoutStartSelection.swift
//  AmakaFlow
//
//  AMA-2291: Start sheet gym + device selection (Garmin primary when paired).
//

import Foundation

/// Device choices offered at Start — Amazfit intentionally omitted (delivery pivot).
enum WorkoutStartDevice: String, CaseIterable, Identifiable, Equatable {
    case garmin
    case apple
    case phone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .garmin: return "Garmin"
        case .apple: return "Apple"
        case .phone: return "Phone"
        }
    }

    var subtitle: String {
        switch self {
        case .garmin: return "Primary — push to watch (AMA-2286)"
        case .apple: return "Try — Watch / WorkoutKit (AMA-2287)"
        case .phone: return "Phone follow-along (AMA-2290)"
        }
    }

    var accessibilityIdentifier: String {
        "af_start_device_\(rawValue)"
    }
}

/// Named gym stub for Proto Start sheet. Honest empty continues when unset.
enum WorkoutStartGym: String, CaseIterable, Identifiable, Equatable {
    case home
    case commercial
    case unset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home gym"
        case .commercial: return "Commercial gym"
        case .unset: return "No gym set"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "Use home equipment profile"
        case .commercial: return "Use gym equipment profile"
        case .unset: return "Continue without a gym — honest empty"
        }
    }

    var accessibilityIdentifier: String {
        "af_start_gym_\(rawValue)"
    }
}

/// Pure Start-sheet defaults — unit-tested without UI.
enum WorkoutStartDefaults {
    /// Garmin is primary when paired; otherwise Phone. Apple is secondary ("try"), never the silent default.
    static func preferredDevice(garminPaired: Bool) -> WorkoutStartDevice {
        garminPaired ? .garmin : .phone
    }

    /// Apple Stay available as try even when Watch is unreachable; callers may disable the row.
    static func isAppleEnabled(watchReachable: Bool) -> Bool {
        // Proto: always offer the try path; label/disabled state handled in the sheet.
        _ = watchReachable
        return true
    }

    static func appleAvailabilityLabel(watchReachable: Bool) -> String {
        watchReachable ? "Try" : "Try — Watch not reachable"
    }
}

/// Where Start confirm should hand off. Full push/player e2e lives in downstream issues.
enum WorkoutStartHandoff: Equatable {
    /// AMA-2286: Garmin one-tap push — wire existing push entry when present.
    case garmin
    /// AMA-2287: Apple Workout / Watch try — sendToWatch / WorkoutKit when present.
    case apple
    /// AMA-2290: strength phone player — use WorkoutEngine + WorkoutPlayerView when present.
    case phone
}

enum WorkoutStartHandoffResolver {
    static func handoff(for device: WorkoutStartDevice) -> WorkoutStartHandoff {
        switch device {
        case .garmin: return .garmin
        case .apple: return .apple
        case .phone: return .phone
        }
    }
}
