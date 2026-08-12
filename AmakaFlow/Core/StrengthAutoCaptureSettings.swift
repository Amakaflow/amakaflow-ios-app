//
//  StrengthAutoCaptureSettings.swift
//  AmakaFlow
//
//  AMA-2420 — experimental Strength auto-capture flag (phone Settings).
//  Watch mirrors via WC `experimentalFlags` → WatchStrengthAutoCaptureSettings.
//

import Foundation

/// Persisted experimental toggle for Watch strength auto-capture.
/// Off by default. Env `AMAKAFLOW_STRENGTH_AUTO_CAPTURE=1` forces on for QA.
enum StrengthAutoCaptureSettings {
    static let defaultsKey = DefaultsKey.strengthAutoCaptureExperimental.rawValue

    static var isEnabled: Bool {
        get {
            if let override = ProcessInfo.processInfo.environment["AMAKAFLOW_STRENGTH_AUTO_CAPTURE"] {
                return override == "1" || override.lowercased() == "true"
            }
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            NotificationCenter.default.post(
                name: .strengthAutoCaptureSettingsDidChange,
                object: nil
            )
        }
    }
}

extension Notification.Name {
    static let strengthAutoCaptureSettingsDidChange =
        Notification.Name("ama2420_strength_auto_capture_settings_did_change")
}
