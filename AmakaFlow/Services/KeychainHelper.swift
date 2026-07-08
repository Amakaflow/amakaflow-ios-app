import Foundation
import Security

// AMA-436: unified secure-storage interface; LiveSecureStorage is the Keychain adapter.

protocol SecureStorageProviding: Sendable {
    @discardableResult func save(_ data: Data, forKey key: String) -> Bool
    func load(forKey key: String) -> Data?
    @discardableResult func delete(forKey key: String) -> Bool
    func exists(forKey key: String) -> Bool
}

/// Keychain-backed implementation of `SecureStorageProviding`.
///
/// All entries use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so that
/// background token refresh can succeed after the device has been unlocked once
/// following a reboot, while preventing iCloud Keychain sync.
final class LiveSecureStorage: SecureStorageProviding, @unchecked Sendable {
    static let shared = LiveSecureStorage(service: "com.amakaflow.companion")

    private let service: String

    init(service: String) {
        self.service = service
    }

    @discardableResult
    func save(_ data: Data, forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func exists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
