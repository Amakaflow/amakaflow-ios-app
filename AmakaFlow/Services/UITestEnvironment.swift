//
//  UITestEnvironment.swift
//  AmakaFlow
//
//  Centralized UITEST environment variable handling
//

import Foundation

/// Centralized management of UITEST environment variables.
///
/// Every read funnels through `value(for:)`, `argumentValue(for:)`, or
/// `fixtureState`, and all three compile to `return nil` outside Debug. A
/// Release binary therefore reports every flag as off no matter what the
/// launch arguments, app defaults, or process environment say. Three call
/// sites were previously reachable in Release, one of which let a defaults
/// key skip the mental-model onboarding gate in a shipping build.
class UITestEnvironment {
    static let shared = UITestEnvironment()
    
    private init() {}

    /// XCTest injects `UITEST_*` via `launchEnvironment`; Maestro 2.x passes
    /// `launchApp.arguments`, which iOS surfaces as UserDefaults keys and/or
    /// raw `ProcessInfo.arguments` entries (`-Key`, `value`).
    ///
    /// Prefer explicit launch arguments / app defaults over the simulator's
    /// process environment — stale `simctl`/scheme env (e.g.
    /// `UITEST_USE_FIXTURES=false`) otherwise shadows intentional dogfood launches.
    static func value(for key: String) -> String? {
        #if !DEBUG
        return nil
        #else
        if let fromArgs = argumentValue(for: key) {
            return fromArgs
        }
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            return stored
        }
        if let stored = UserDefaults.standard.string(forKey: "-\(key)"), !stored.isEmpty {
            return stored
        }
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        return nil
        #endif
    }

    /// `simctl launch … -FLAG true` sometimes drops the value token; a bare
    /// `-FLAG` followed by another `-Next` still means the flag was requested.
    private static func argumentValue(for key: String) -> String? {
        #if !DEBUG
        return nil
        #else
        let args = ProcessInfo.processInfo.arguments
        for index in args.indices {
            let token = args[index]
            guard token == key || token == "-\(key)" else { continue }
            let next = index + 1
            if next < args.count, !args[next].hasPrefix("-") {
                return args[next]
            }
            // Present as a bare flag → treat as enabled.
            return "true"
        }
        return nil
        #endif
    }

    static func isTruthy(_ key: String) -> Bool {
        guard let raw = value(for: key)?.lowercased() else { return false }
        return raw == "true" || raw == "1" || raw == "yes"
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
    /// Ignore stale simulator env `empty` when launch args/defaults name fixtures —
    /// otherwise dogfood launches load zero workouts while Library still looks "live".
    var fixtureState: String? {
        #if !DEBUG
        return nil
        #else
        if Self.argumentValue(for: "UITEST_FIXTURE_STATE") != nil {
            let state = Self.argumentValue(for: "UITEST_FIXTURE_STATE")
            return state?.isEmpty == false ? state : nil
        }
        if let stored = UserDefaults.standard.string(forKey: "UITEST_FIXTURE_STATE"), !stored.isEmpty {
            return stored
        }
        if fixtureNames != nil {
            return nil
        }
        let state = ProcessInfo.processInfo.environment["UITEST_FIXTURE_STATE"]
        return state?.isEmpty == false ? state : nil
        #endif
    }

    /// Skip onboarding/mental model gates during UI tests.
    var skipOnboarding: Bool {
        Self.isTruthy("UITEST_SKIP_ONBOARDING")
    }

    /// Skip Apple Watch setup during UI tests.
    var skipAppleWatch: Bool {
        Self.isTruthy("UITEST_SKIP_APPLE_WATCH") || Self.isTruthy("UITEST_FAKE_WATCH")
    }

    /// AMA-2375: force Library door + watch manager screens with fixture data (simulator dogfood).
    var forceWatchManagerDemo: Bool {
        Self.isTruthy("UITEST_FORCE_WATCH_MANAGER") || Self.isTruthy("AMA2375_DEMO")
    }

    /// DEBUG visual host: show Create-with-AI generating chrome without auth.
    var showCreateWithAIGeneratingHost: Bool {
        Self.isTruthy("UITEST_SHOW_CREATE_WITH_AI_GENERATING")
    }

    /// DEBUG visual host: AMA-2387 Actuals dogfood hub (no Clerk / live OAuth).
    /// AMA-2426: `AMA2426_DEMO` opens the same hub (includes Logbook mock fill-in).
    var showActualsDogfoodHost: Bool {
        Self.isTruthy("AMA2387_DEMO")
            || Self.isTruthy("AMA2426_DEMO")
            || Self.isTruthy("UITEST_SHOW_ACTUALS_DOGFOOD")
    }

    /// DEBUG: seed Actuals merge/map/fill-in cards on real Today (after connect or cold).
    var actualsTodayDemo: Bool {
        Self.isTruthy("AMA2387_TODAY_DEMO")
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