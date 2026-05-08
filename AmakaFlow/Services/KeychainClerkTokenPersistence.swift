import Foundation
import Security

/// AMA-1809: Keychain-backed persistence for the Clerk auth token.
///
/// The previous default `UserDefaultsClerkTokenPersistence` writes the bearer
/// token into a property list readable by anything with the app's container
/// (including a backup of an unencrypted device). Keychain entries are
/// hardware-encrypted, scoped to this device only, and survive the
/// container-clearing reset.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` lets background
/// refresh succeed after a reboot once the user has unlocked once, while
/// `ThisDeviceOnly` keeps the token from syncing to iCloud Keychain.
final class KeychainClerkTokenPersistence: ClerkTokenPersistence, @unchecked Sendable {

    private let service: String
    private let account: String
    private let legacyDefaults: UserDefaults?
    private let legacyKey: String?

    /// - Parameters:
    ///   - service: keychain service identifier — defaults to the app bundle's keychain namespace.
    ///   - account: keychain account key — single-token store, not multi-user.
    ///   - legacyDefaults / legacyKey: when both are non-nil, `loadClerkToken`
    ///     will perform a one-shot migration from the legacy UserDefaults
    ///     storage on first read, then clear the UserDefaults entry. Pass
    ///     `nil` for both in tests that don't want migration behaviour.
    init(
        service: String = "com.amakaflow.companion.clerk",
        account: String = "clerk_auth_token",
        legacyDefaults: UserDefaults? = .standard,
        legacyKey: String? = "clerk_auth_token"
    ) {
        self.service = service
        self.account = account
        self.legacyDefaults = legacyDefaults
        self.legacyKey = legacyKey
    }

    // MARK: - ClerkTokenPersistence

    func loadClerkToken() -> ClerkAuthToken? {
        if let token = readKeychain() {
            return token
        }
        // One-shot migration from UserDefaults → Keychain.
        if let migrated = migrateFromLegacyDefaults() {
            return migrated
        }
        return nil
    }

    func saveClerkToken(_ token: ClerkAuthToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            _ = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func clearClerkToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
        // Also wipe the legacy UD slot in case migration never ran.
        if let legacyDefaults, let legacyKey {
            legacyDefaults.removeObject(forKey: legacyKey)
        }
    }

    // MARK: - Private

    private func readKeychain() -> ClerkAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ClerkAuthToken.self, from: data)
    }

    private func migrateFromLegacyDefaults() -> ClerkAuthToken? {
        guard let legacyDefaults, let legacyKey,
              let data = legacyDefaults.data(forKey: legacyKey),
              let token = try? JSONDecoder().decode(ClerkAuthToken.self, from: data)
        else { return nil }
        saveClerkToken(token)
        legacyDefaults.removeObject(forKey: legacyKey)
        return token
    }
}
