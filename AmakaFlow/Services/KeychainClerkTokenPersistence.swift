import Foundation

/// AMA-1809: Keychain-backed persistence for the Clerk auth token.
///
/// Builds token-specific logic (JSON encode/decode, UserDefaults migration,
/// App Group mirroring) on top of the unified `SecureStorageProviding` interface.
final class KeychainClerkTokenPersistence: ClerkTokenPersistence, @unchecked Sendable {

    private static let tokenKey = "clerk_auth_token"

    private let storage: SecureStorageProviding
    private let legacyDefaults: UserDefaults?
    private let legacyKey: String?
    private let sharedDefaults: UserDefaults?
    private let sharedDefaultsTokenKey: String

    /// - Parameters:
    ///   - storage: `SecureStorageProviding` adapter — defaults to the live Keychain
    ///     scoped to `com.amakaflow.companion.clerk`. Pass a `MockSecureStorage` in tests.
    ///   - legacyDefaults / legacyKey: when both are non-nil, `loadClerkToken`
    ///     performs a one-shot migration from the legacy UserDefaults storage on
    ///     first read, then clears the UserDefaults entry. Pass `nil` for both
    ///     in tests that don't want migration behaviour.
    ///   - sharedDefaults / sharedDefaultsTokenKey: App Group UserDefaults suite
    ///     where the raw bearer token string is mirrored so the share extension
    ///     can read it via `SharedContainerManager.readAuthToken()`.
    init(
        storage: SecureStorageProviding = LiveSecureStorage(service: "com.amakaflow.companion.clerk"),
        legacyDefaults: UserDefaults? = .standard,
        legacyKey: String? = "clerk_auth_token",
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: "group.com.amakaflow.companion"),
        sharedDefaultsTokenKey: String = "auth_token"
    ) {
        self.storage = storage
        self.legacyDefaults = legacyDefaults
        self.legacyKey = legacyKey
        self.sharedDefaults = sharedDefaults
        self.sharedDefaultsTokenKey = sharedDefaultsTokenKey
    }

    // MARK: - ClerkTokenPersistence

    func loadClerkToken() -> ClerkAuthToken? {
        if let token = readStorage() {
            return token
        }
        if let migrated = migrateFromLegacyDefaults() {
            return migrated
        }
        return nil
    }

    func saveClerkToken(_ token: ClerkAuthToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        storage.save(data, forKey: Self.tokenKey)

        // Mirror the raw bearer token string to the App Group shared container so
        // the share extension can read it via SharedContainerManager.readAuthToken().
        sharedDefaults?.set(token.value, forKey: sharedDefaultsTokenKey)
    }

    func clearClerkToken() {
        storage.delete(forKey: Self.tokenKey)
        // Also wipe the legacy UD slot in case migration never ran.
        if let legacyDefaults, let legacyKey {
            legacyDefaults.removeObject(forKey: legacyKey)
        }
        // Clear the App Group mirror so the share extension can't use a stale token.
        sharedDefaults?.removeObject(forKey: sharedDefaultsTokenKey)
    }

    // MARK: - Private

    private func readStorage() -> ClerkAuthToken? {
        guard let data = storage.load(forKey: Self.tokenKey) else { return nil }
        return try? JSONDecoder().decode(ClerkAuthToken.self, from: data)
    }

    private func migrateFromLegacyDefaults() -> ClerkAuthToken? {
        guard let legacyDefaults, let legacyKey,
              let data = legacyDefaults.data(forKey: legacyKey),
              let token = try? JSONDecoder().decode(ClerkAuthToken.self, from: data)
        else { return nil }
        saveClerkToken(token)
        // AMA-1809 (CR): only wipe the legacy entry once the storage write is
        // confirmed. If the write failed silently, destroying the UserDefaults
        // copy would force the user to re-authenticate.
        guard readStorage() == token else { return nil }
        legacyDefaults.removeObject(forKey: legacyKey)
        return token
    }
}
