import Foundation
@testable import AmakaFlowCompanion

// AMA-436: in-memory SecureStorageProviding for tests — no Keychain access required.
final class MockSecureStorage: SecureStorageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]

    @discardableResult
    func save(_ data: Data, forKey key: String) -> Bool {
        lock.withLock { store[key] = data }
        return true
    }

    func load(forKey key: String) -> Data? {
        lock.withLock { store[key] }
    }

    @discardableResult
    func delete(forKey key: String) -> Bool {
        lock.withLock { store[key] = nil }
        return true
    }

    func exists(forKey key: String) -> Bool {
        lock.withLock { store[key] != nil }
    }
}

extension NSLock {
    @discardableResult
    fileprivate func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
