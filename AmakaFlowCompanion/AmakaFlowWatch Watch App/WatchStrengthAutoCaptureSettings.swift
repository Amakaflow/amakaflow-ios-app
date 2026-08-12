//
//  WatchStrengthAutoCaptureSettings.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 — Watch-side mirror of the phone Experimental Strength toggle.
//

import Foundation

enum WatchStrengthAutoCaptureSettings {
    static let defaultsKey = "ama2420_strength_auto_capture_experimental"
    static let didChangeNotification = Notification.Name("ama2420_strength_auto_capture_did_change")

    static var isEnabled: Bool {
        get {
            if let override = ProcessInfo.processInfo.environment["AMAKAFLOW_STRENGTH_AUTO_CAPTURE"] {
                return override == "1" || override.lowercased() == "true"
            }
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    static func apply(from message: [String: Any]) {
        if let enabled = message["strengthAutoCapture"] as? Bool {
            let previous = UserDefaults.standard.bool(forKey: defaultsKey)
            isEnabled = enabled
            print("⌚️ Strength auto-capture experimental=\(enabled)")
            if previous != enabled {
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
        }
    }
}
