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
    
    // MARK: - Environment Variable Access
    
    /// Check if login bypass is enabled
    var isLoginBypassEnabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_LOGIN_BYPASS"]?.lowercased() == "true"
    }
    
    /// Get simulation speed multiplier (1.0 = normal, 2.0 = 2x speed, etc.)
    var simulationSpeed: Double {
        if let speedStr = ProcessInfo.processInfo.environment["UITEST_SIM_SPEED"],
           let speed = Double(speedStr), speed > 0 {
            return speed
        }
        return 1.0 // Default to normal speed
    }
    
    /// Check if fake watch connectivity should be used
    var useFakeWatchConnectivity: Bool {
        ProcessInfo.processInfo.environment["UITEST_FAKE_WATCH"]?.lowercased() == "true"
    }
    
    /// Check if Sentry should be disabled
    var isSentryDisabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_DISABLE_SENTRY"]?.lowercased() == "true"
    }
    

    /// Fixture-backed app mode for deterministic UI tests.
    var useFixtures: Bool {
        ProcessInfo.processInfo.environment["UITEST_USE_FIXTURES"]?.lowercased() == "true"
    }

    /// Comma-separated fixture names, without .json extensions.
    var fixtureNames: [String]? {
        guard let raw = ProcessInfo.processInfo.environment["UITEST_FIXTURES"], !raw.isEmpty else { return nil }
        let names = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }

    /// Special fixture state: empty, error, etc.
    var fixtureState: String? {
        let state = ProcessInfo.processInfo.environment["UITEST_FIXTURE_STATE"]
        return state?.isEmpty == false ? state : nil
    }

    /// Skip onboarding/mental model gates during UI tests.
    var skipOnboarding: Bool {
        ProcessInfo.processInfo.environment["UITEST_SKIP_ONBOARDING"]?.lowercased() == "true"
    }

    /// Skip Apple Watch setup during UI tests.
    var skipAppleWatch: Bool {
        ProcessInfo.processInfo.environment["UITEST_SKIP_APPLE_WATCH"]?.lowercased() == "true"
            || ProcessInfo.processInfo.environment["UITEST_FAKE_WATCH"]?.lowercased() == "true"
    }

    /// Clerk-backed UI tests should sign in as a real Clerk test user instead of using header bypasses.
    var hasClerkTestUser: Bool {
        guard ProcessInfo.processInfo.environment["UITEST_CLERK_EMAIL"]?.isEmpty == false,
              ProcessInfo.processInfo.environment["UITEST_CLERK_PASSWORD"]?.isEmpty == false,
              ProcessInfo.processInfo.environment["UITEST_CLERK_PUBLISHABLE_KEY"]?.isEmpty == false
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
        print("  - Login Bypass: \(isLoginBypassEnabled)")
        print("  - Simulation Speed: \(simulationSpeed)x")
        print("  - Fake Watch: \(useFakeWatchConnectivity)")
        print("  - Fixtures: \(useFixtures)")
        print("  - Clerk Test User: \(hasClerkTestUser)")
        print("  - Sentry Disabled: \(isSentryDisabled)")
        #endif
    }
}