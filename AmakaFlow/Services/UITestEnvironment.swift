//
//  UITestEnvironment.swift
//  AmakaFlow
//
//  Centralized UITEST environment variable handling
//

import Foundation

/// Centralized management of UITEST environment variables
class UITestEnvironment {
    static let shared = UITestEnvironment()
    
    private init() {}

    /// XCTest injects `UITEST_*` via `launchEnvironment`; Maestro 2.x passes
    /// `launchApp.arguments`, which iOS surfaces as UserDefaults keys and/or
    /// raw `ProcessInfo.arguments` entries (`-Key`, `value`).
    static func value(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            return stored
        }
        let args = ProcessInfo.processInfo.arguments
        for index in args.indices {
            let token = args[index]
            if token == key || token == "-\(key)" {
                let next = index + 1
                if next < args.count, !args[next].hasPrefix("-") {
                    return args[next]
                }
            }
        }
        return nil
    }

    static func isTruthy(_ key: String) -> Bool {
        value(for: key)?.lowercased() == "true"
    }
    
    // MARK: - Environment Variable Access

    /// Get simulation speed multiplier (1.0 = normal, 2.0 = 2x speed, etc.)
    var simulationSpeed: Double {
        if let speedStr = Self.value(for: "UITEST_SIM_SPEED"),
           let speed = Double(speedStr), speed > 0 {
            return speed
        }
        return 1.0 // Default to normal speed
    }
    
    /// Check if fake watch connectivity should be used
    var useFakeWatchConnectivity: Bool {
        Self.isTruthy("UITEST_FAKE_WATCH")
    }
    
    /// Check if Sentry should be disabled
    var isSentryDisabled: Bool {
        Self.isTruthy("UITEST_DISABLE_SENTRY")
    }
    

    /// Fixture-backed app mode for deterministic UI tests.
    var useFixtures: Bool {
        Self.isTruthy("UITEST_USE_FIXTURES")
    }

    /// Comma-separated fixture names, without .json extensions.
    var fixtureNames: [String]? {
        guard let raw = Self.value(for: "UITEST_FIXTURES"), !raw.isEmpty else { return nil }
        let names = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }

    /// Special fixture state: empty, error, etc.
    var fixtureState: String? {
        let state = Self.value(for: "UITEST_FIXTURE_STATE")
        return state?.isEmpty == false ? state : nil
    }

    /// Skip onboarding/mental model gates during UI tests.
    var skipOnboarding: Bool {
        Self.isTruthy("UITEST_SKIP_ONBOARDING")
    }

    /// Skip Apple Watch setup during UI tests.
    var skipAppleWatch: Bool {
        Self.isTruthy("UITEST_SKIP_APPLE_WATCH") || Self.isTruthy("UITEST_FAKE_WATCH")
    }

    /// Clerk-backed UI tests should sign in as a real Clerk test user instead of using header bypasses.
    var hasClerkTestUser: Bool {
        guard Self.value(for: "UITEST_CLERK_EMAIL")?.isEmpty == false,
              Self.value(for: "UITEST_CLERK_PASSWORD")?.isEmpty == false,
              Self.value(for: "UITEST_CLERK_PUBLISHABLE_KEY")?.isEmpty == false
        else { return false }
        return true
    }

    // MARK: - Utility Methods
    
    /// Get adjusted duration for animations/timers based on simulation speed
    func adjustedDuration(_ originalDuration: TimeInterval) -> TimeInterval {
        return originalDuration / simulationSpeed
    }
    
    /// Get adjusted delay for async operations
    func adjustedDelay(_ originalDelay: TimeInterval) -> TimeInterval {
        return originalDelay / simulationSpeed
    }
    
    /// Print current UITEST configuration for debugging
    func printConfiguration() {
        #if DEBUG
        print("[UITestEnvironment] Configuration:")
        print("  - Simulation Speed: \(simulationSpeed)x")
        print("  - Fake Watch: \(useFakeWatchConnectivity)")
        print("  - Fixtures: \(useFixtures)")
        print("  - Clerk Test User: \(hasClerkTestUser)")
        print("  - Sentry Disabled: \(isSentryDisabled)")
        #endif
    }
}