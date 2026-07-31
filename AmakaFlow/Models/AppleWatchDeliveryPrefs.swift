//
//  AppleWatchDeliveryPrefs.swift
//  AmakaFlow
//
//  AMA-2360 / AMA-2349 — Apple Watch delivery prefs (tap/timed rest; no Garmin lap).
//

import Foundation

/// How work sets finish in Apple Workout (WorkoutKit).
/// Deliberate ease-first: no Garmin `lap` / timed-everything.
enum AppleExerciseEnd: String, CaseIterable, Codable, Identifiable {
    case tap
    case timedHoldsOnly = "timed_holds_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tap:
            return "Tap when the set is done"
        case .timedHoldsOnly:
            return "Timed holds only (planks, etc.); otherwise tap"
        }
    }
}

/// How between-set rest appears on Apple Watch.
enum AppleRestMode: String, CaseIterable, Codable, Identifiable {
    case timed
    case tap
    case omit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timed:
            return "Countdown from the workout rest"
        case .tap:
            return "Tap when you’re ready"
        case .omit:
            return "No rest steps — I’ll rest on my own"
        }
    }
}

/// Persisted Apple WorkoutKit delivery preferences (AMA-2349 / AMA-2360).
struct AppleWatchDeliveryPrefs: Equatable, Codable {
    var exerciseEnd: AppleExerciseEnd
    var restMode: AppleRestMode
    var alertsEnabled: Bool

    /// Strength dogfood defaults from spec §5.
    static let dogfood = AppleWatchDeliveryPrefs(
        exerciseEnd: .tap,
        restMode: .timed,
        alertsEnabled: false
    )

    var summaryLine: String {
        let work: String
        switch exerciseEnd {
        case .tap: work = "Tap to advance"
        case .timedHoldsOnly: work = "Timed holds · else tap"
        }
        let rest: String
        switch restMode {
        case .timed: rest = "Rest timed"
        case .tap: rest = "Rest until tap"
        case .omit: rest = "No rest steps"
        }
        let alerts = alertsEnabled ? "Alerts on" : "Alerts off"
        return "\(work) · \(rest) · \(alerts)"
    }

    /// Body fields for BFF/mapper `delivery_prefs`.
    var deliveryPrefsDictionary: [String: Any] {
        [
            "exercise_end": exerciseEnd.rawValue,
            "rest_mode": restMode.rawValue,
            "alerts_enabled": alertsEnabled
        ]
    }
}

/// UserDefaults-backed store for Apple Watch delivery prefs.
enum AppleWatchDeliveryPrefsStore {
    private static var defaults: UserDefaults { .standard }

    static var hasConfigured: Bool {
        get { defaults.bool(forKey: DefaultsKey.appleWatchDeliveryPrefsConfigured.rawValue) }
        set { defaults.set(newValue, forKey: DefaultsKey.appleWatchDeliveryPrefsConfigured.rawValue) }
    }

    static var current: AppleWatchDeliveryPrefs {
        get {
            guard
                let data = defaults.data(forKey: DefaultsKey.appleWatchDeliveryPrefs.rawValue),
                let decoded = try? JSONDecoder().decode(AppleWatchDeliveryPrefs.self, from: data)
            else {
                return .dogfood
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: DefaultsKey.appleWatchDeliveryPrefs.rawValue)
            }
            hasConfigured = true
        }
    }

    /// JSON body for mapper `delivery_prefs`, or `nil` so backend sport defaults apply
    /// until the user has saved prefs at least once (AMA-2360 / CodeRabbit).
    static var deliveryPrefsForMapper: [String: Any]? {
        hasConfigured ? current.deliveryPrefsDictionary : nil
    }

    /// Preview / Start sheet line — distinguishes unset vs customized.
    static var previewSummaryLine: String {
        hasConfigured
            ? current.summaryLine
            : "Mapper sport defaults (not customized)"
    }

    static func applyLiveSelection(
        exerciseEnd: AppleExerciseEnd? = nil,
        restMode: AppleRestMode? = nil,
        alertsEnabled: Bool? = nil
    ) {
        var next = current
        if let exerciseEnd { next.exerciseEnd = exerciseEnd }
        if let restMode { next.restMode = restMode }
        if let alertsEnabled { next.alertsEnabled = alertsEnabled }
        current = next
    }

    static func resetForTests() {
        defaults.removeObject(forKey: DefaultsKey.appleWatchDeliveryPrefs.rawValue)
        defaults.removeObject(forKey: DefaultsKey.appleWatchDeliveryPrefsConfigured.rawValue)
    }
}
