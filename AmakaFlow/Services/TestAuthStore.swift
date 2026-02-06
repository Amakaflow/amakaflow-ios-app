//
//  TestAuthStore.swift
//  AmakaFlow
//
//  Stores test authentication credentials for E2E testing bypass.
//  Allows manual entry of test credentials on simulators to skip QR pairing.
//

import Foundation

/// Store for E2E test authentication credentials
/// Supports both environment variables (automated tests) and runtime storage (manual testing)
class TestAuthStore {
    static let shared = TestAuthStore()

    private let authSecretKey = "e2e_test_auth_secret"
    private let userIdKey = "e2e_test_user_id"
    private let userEmailKey = "e2e_test_user_email"

    private init() {}

    // MARK: - Launch Argument Helper

    /// Read a UITEST_* value from launch arguments (injected via UserDefaults by Maestro 2.1.0)
    private func launchArgument(_ key: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: key),
              !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Credential Access

    /// Get the test auth secret (checks environment first, then launch args, then stored value)
    var authSecret: String? {
        #if DEBUG
        // UITEST_* env vars take highest precedence (Maestro E2E tests)
        if let envSecret = ProcessInfo.processInfo.environment["UITEST_AUTH_SECRET"],
           !envSecret.isEmpty {
            return envSecret
        }
        // Launch arguments next (Maestro 2.1.0 injects via UserDefaults)
        if let argSecret = launchArgument("UITEST_AUTH_SECRET") {
            return argSecret
        }
        // TEST_* env vars next (xcodebuild / simctl tests)
        if let envSecret = ProcessInfo.processInfo.environment["TEST_AUTH_SECRET"],
           !envSecret.isEmpty {
            return envSecret
        }
        // Fall back to stored value (for manual testing)
        return UserDefaults.standard.string(forKey: authSecretKey)
        #else
        return nil
        #endif
    }

    /// Get the test user ID (checks environment first, then launch args, then stored value)
    var userId: String? {
        #if DEBUG
        // UITEST_* env vars take highest precedence (Maestro E2E tests)
        if let envUserId = ProcessInfo.processInfo.environment["UITEST_USER_ID"],
           !envUserId.isEmpty {
            return envUserId
        }
        // Launch arguments next (Maestro 2.1.0 injects via UserDefaults)
        if let argUserId = launchArgument("UITEST_USER_ID") {
            return argUserId
        }
        // TEST_* env vars next (xcodebuild / simctl tests)
        if let envUserId = ProcessInfo.processInfo.environment["TEST_USER_ID"],
           !envUserId.isEmpty {
            return envUserId
        }
        // Fall back to stored value
        return UserDefaults.standard.string(forKey: userIdKey)
        #else
        return nil
        #endif
    }

    /// Get the test user email (checks environment first, then launch args, then stored value)
    var userEmail: String? {
        #if DEBUG
        // UITEST_* env vars take highest precedence (Maestro E2E tests)
        if let envEmail = ProcessInfo.processInfo.environment["UITEST_USER_EMAIL"],
           !envEmail.isEmpty {
            return envEmail
        }
        // Launch arguments next (Maestro 2.1.0 injects via UserDefaults)
        if let argEmail = launchArgument("UITEST_USER_EMAIL") {
            return argEmail
        }
        // TEST_* env vars next (xcodebuild / simctl tests)
        if let envEmail = ProcessInfo.processInfo.environment["TEST_USER_EMAIL"],
           !envEmail.isEmpty {
            return envEmail
        }
        // Fall back to stored value
        return UserDefaults.standard.string(forKey: userEmailKey)
        #else
        return nil
        #endif
    }

    /// Check if test mode is enabled (either via env vars or stored credentials)
    var isTestModeEnabled: Bool {
        #if DEBUG
        return authSecret != nil && userId != nil
        #else
        return false
        #endif
    }

    /// Check if using stored credentials (not environment variables or launch arguments)
    var isUsingStoredCredentials: Bool {
        #if DEBUG
        // Check if we have stored credentials and NOT environment variables or launch arguments
        let hasEnvCredentials = ProcessInfo.processInfo.environment["UITEST_AUTH_SECRET"] != nil
            || ProcessInfo.processInfo.environment["TEST_AUTH_SECRET"] != nil
        let hasLaunchArgCredentials = launchArgument("UITEST_AUTH_SECRET") != nil
        let hasStoredCredentials = UserDefaults.standard.string(forKey: authSecretKey) != nil
        return hasStoredCredentials && !hasEnvCredentials && !hasLaunchArgCredentials
        #else
        return false
        #endif
    }

    /// Whether Maestro tests should load fixture data instead of calling the API
    var useFixtures: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["UITEST_USE_FIXTURES"] == "true"
            || launchArgument("UITEST_USE_FIXTURES") == "true"
        #else
        return false
        #endif
    }

    /// Comma-separated fixture filenames to load (without .json extension)
    /// When nil, all bundled fixtures are loaded
    var fixtureNames: [String]? {
        #if DEBUG
        let value = ProcessInfo.processInfo.environment["UITEST_FIXTURES"]
            ?? launchArgument("UITEST_FIXTURES")
        guard let value, !value.isEmpty else { return nil }
        return value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        #else
        return nil
        #endif
    }

    /// Special fixture state: "empty" (no workouts) or "error" (simulate API failure)
    var fixtureState: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["UITEST_FIXTURE_STATE"]
            ?? launchArgument("UITEST_FIXTURE_STATE")
        #else
        return nil
        #endif
    }

    /// Whether onboarding screens should be skipped (forward-compatible, no onboarding screens exist yet)
    var skipOnboarding: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["UITEST_SKIP_ONBOARDING"] == "true"
            || launchArgument("UITEST_SKIP_ONBOARDING") == "true"
        #else
        return false
        #endif
    }

    // MARK: - Credential Storage

    /// Store test credentials for manual E2E testing
    /// - Parameters:
    ///   - authSecret: The test auth secret
    ///   - userId: The test user ID
    ///   - email: Optional user email
    func storeCredentials(authSecret: String, userId: String, email: String? = nil) {
        #if DEBUG
        UserDefaults.standard.set(authSecret, forKey: authSecretKey)
        UserDefaults.standard.set(userId, forKey: userIdKey)
        if let email = email {
            UserDefaults.standard.set(email, forKey: userEmailKey)
        }
        print("[TestAuthStore] Stored E2E test credentials for user: \(userId)")
        #endif
    }

    /// Clear stored test credentials
    func clearCredentials() {
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: authSecretKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        print("[TestAuthStore] Cleared E2E test credentials")
        #endif
    }
}
