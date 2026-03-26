//
//  SharedContainerManager.swift
//  AmakaFlowShare
//
//  Manages the App Group shared container for data handoff between the share extension and main app.
//  AMA-1257: iOS Share Extension — one-tap workout import from any app
//

import Foundation

/// Manages read/write to the App Group shared container
enum SharedContainerManager {

    /// App Group suite name — must match the main app's entitlement
    static let suiteName = "group.com.amakaflow.companion"

    /// Key for the array of pending import results
    private static let pendingImportsKey = "pending_workout_imports"

    /// Key for the auth token written by the main app
    static let authTokenKey = "auth_token"

    /// Key for the test auth secret (E2E testing)
    static let testAuthSecretKey = "test_auth_secret"

    /// Key for the test user ID (E2E testing)
    static let testUserIdKey = "test_user_id"

    /// Key for the app environment (development/staging/production)
    static let appEnvironmentKey = "app_environment"

    // MARK: - UserDefaults Accessor

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Auth Credentials (read by extension, written by main app)

    /// Read the JWT auth token from the shared container
    static func readAuthToken() -> String? {
        sharedDefaults?.string(forKey: authTokenKey)
    }

    /// Read test auth credentials (E2E)
    static func readTestAuth() -> (secret: String, userId: String)? {
        guard let secret = sharedDefaults?.string(forKey: testAuthSecretKey),
              !secret.isEmpty,
              let userId = sharedDefaults?.string(forKey: testUserIdKey) else {
            return nil
        }
        return (secret, userId)
    }

    /// Read the current app environment
    static func readEnvironment() -> String {
        sharedDefaults?.string(forKey: appEnvironmentKey) ?? "staging"
    }

    // MARK: - Pending Import Results

    /// A single import result stored in the shared container
    struct ImportResult: Codable {
        let url: String
        let platform: String
        let title: String?
        let workoutType: String?
        let success: Bool
        let errorMessage: String?
        let timestamp: Date
    }

    /// Append a new import result to the pending list
    static func saveImportResult(_ result: ImportResult) {
        guard let defaults = sharedDefaults else { return }

        var existing = readPendingImports()
        existing.append(result)

        // Keep at most 50 results to avoid bloating UserDefaults
        if existing.count > 50 {
            existing = Array(existing.suffix(50))
        }

        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: pendingImportsKey)
        }
    }

    /// Read all pending import results
    static func readPendingImports() -> [ImportResult] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: pendingImportsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([ImportResult].self, from: data)) ?? []
    }

    /// Clear all pending import results (called by main app after processing)
    static func clearPendingImports() {
        sharedDefaults?.removeObject(forKey: pendingImportsKey)
    }

    /// Remove a specific import result by URL and timestamp
    static func removeImportResult(url: String, timestamp: Date) {
        var results = readPendingImports()
        results.removeAll { $0.url == url && $0.timestamp == timestamp }
        if let data = try? JSONEncoder().encode(results) {
            sharedDefaults?.set(data, forKey: pendingImportsKey)
        }
    }
}
