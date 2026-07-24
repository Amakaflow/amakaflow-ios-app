//
//  GarminWatchDisplayPrefs.swift
//  AmakaFlow
//
//  AMA-2316: One-time Garmin watch display prefs (work end + between-set rest).
//

import Foundation

/// How work sets finish on Garmin's native workout player.
enum GarminExerciseEnd: String, CaseIterable, Codable, Identifiable {
    /// Work step OPEN / until lap (dogfood default).
    case lap
    /// Still OPEN; title includes compact Rx (`×8` / `3×8`).
    case showRepsLap = "show_reps_lap"
    /// Duration steps timed; strength reps stay lap.
    case timedHoldsOnly = "timed_holds_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lap:
            return "Press Lap when the set is done"
        case .showRepsLap:
            return "Show reps, then press Lap when done"
        case .timedHoldsOnly:
            return "Timed holds only (planks, etc.); otherwise Lap"
        }
    }
}

/// How between-set rest appears on the watch.
enum GarminRestMode: String, CaseIterable, Codable, Identifiable {
    /// Timed from prescription; missing → defaultRestSec (dogfood default).
    case timed
    /// Rest OPEN / until lap.
    case lap
    /// Omit between-set rest steps.
    case omit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timed:
            return "Countdown from the workout rest"
        case .lap:
            return "Press Lap when you’re ready"
        case .omit:
            return "No rest steps — I’ll rest on my own"
        }
    }
}

/// Persisted Garmin FIT display preferences (AMA-2316).
struct GarminWatchDisplayPrefs: Equatable, Codable {
    var exerciseEnd: GarminExerciseEnd
    var restMode: GarminRestMode
    /// Used when restMode == .timed and Rx rest is missing.
    var defaultRestSec: Int

    static let dogfood = GarminWatchDisplayPrefs(
        exerciseEnd: .lap,
        restMode: .timed,
        defaultRestSec: 60
    )

    /// One-line summary for Start sheet / Settings.
    var summaryLine: String {
        let work: String
        switch exerciseEnd {
        case .lap: work = "Lap to advance"
        case .showRepsLap: work = "Show reps · Lap to advance"
        case .timedHoldsOnly: work = "Timed holds · else Lap"
        }
        let rest: String
        switch restMode {
        case .timed: rest = "Rest timed (\(defaultRestSec)s if not prescribed)"
        case .lap: rest = "Rest until Lap"
        case .omit: rest = "No rest steps"
        }
        return "\(work) · \(rest)"
    }

    /// JSON body fields for POST watch-delivery push (mapper PushBody).
    var pushBody: GarminWatchDeliveryPushBody {
        GarminWatchDeliveryPushBody(prefs: self)
    }
}

/// Mapper/BFF `PushBody` fields for AMA-2316 display prefs.
struct GarminWatchDeliveryPushBody: Encodable, Equatable, Sendable {
    let exerciseEnd: String
    let restMode: String
    let defaultRestSec: Int

    enum CodingKeys: String, CodingKey {
        case exerciseEnd = "exercise_end"
        case restMode = "rest_mode"
        case defaultRestSec = "default_rest_sec"
    }

    init(prefs: GarminWatchDisplayPrefs) {
        exerciseEnd = prefs.exerciseEnd.rawValue
        restMode = prefs.restMode.rawValue
        defaultRestSec = prefs.defaultRestSec
    }
}

/// UserDefaults-backed store for Garmin watch display prefs.
enum GarminWatchDisplayPrefsStore {
    private static var defaults: UserDefaults { .standard }

    static var hasConfigured: Bool {
        get { defaults.bool(forKey: DefaultsKey.garminWatchDisplayPrefsConfigured.rawValue) }
        set { defaults.set(newValue, forKey: DefaultsKey.garminWatchDisplayPrefsConfigured.rawValue) }
    }

    static var current: GarminWatchDisplayPrefs {
        get {
            guard
                let data = defaults.data(forKey: DefaultsKey.garminWatchDisplayPrefs.rawValue),
                let decoded = try? JSONDecoder().decode(GarminWatchDisplayPrefs.self, from: data)
            else {
                return .dogfood
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: DefaultsKey.garminWatchDisplayPrefs.rawValue)
            }
            hasConfigured = true
        }
    }

    /// Whether the one-time Connect sheet should appear after a successful pair.
    static var shouldPresentOnboarding: Bool {
        !hasConfigured
    }

    static func resetForTests() {
        defaults.removeObject(forKey: DefaultsKey.garminWatchDisplayPrefs.rawValue)
        defaults.removeObject(forKey: DefaultsKey.garminWatchDisplayPrefsConfigured.rawValue)
    }
}
