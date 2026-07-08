import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class ClerkTokenRefreshTests: XCTestCase {
  private var now: Date!
  private var client: MockClerkTokenRefreshClient!
  private var persistence: InMemoryClerkTokenPersistence!
  private var coordinator: ClerkTokenRefreshCoordinator!

  override func setUp() {
    super.setUp()
    now = Date(timeIntervalSince1970: 1_700_000_000)
    client = MockClerkTokenRefreshClient()
    persistence = InMemoryClerkTokenPersistence()
    coordinator = makeCoordinator()
  }

  override func tearDown() {
    coordinator = nil
    persistence = nil
    client = nil
    now = nil
    super.tearDown()
  }

  func testBearerToken_usesPersistedTokenWhenOutsideRefreshWindow() async throws {
    persistence.savedToken = token("cached", expiresIn: 10 * 60)

    let value = try await coordinator.bearerToken()

    XCTAssertEqual(value, "cached")
    XCTAssertEqual(client.refreshCallCount, 0)
    let needsReauth = await coordinator.isReauthRequired()
    XCTAssertFalse(needsReauth)
  }

  func testBearerToken_refreshesWhenTokenIsInsideRefreshWindowWithClockSkew() async throws {
    persistence.savedToken = token("stale", expiresIn: 89)
    client.enqueue(.success(token("fresh", expiresIn: 10 * 60)))

    let value = try await coordinator.bearerToken()

    XCTAssertEqual(value, "fresh")
    XCTAssertEqual(client.refreshCallCount, 1)
    XCTAssertEqual(persistence.savedToken?.value, "fresh")
    let needsReauth = await coordinator.isReauthRequired()
    XCTAssertFalse(needsReauth)
  }

  func testBearerToken_keepsTokenAtExactRefreshBoundaryRefreshing() async throws {
    persistence.savedToken = token("boundary", expiresIn: 90)
    client.enqueue(.success(token("fresh-boundary", expiresIn: 10 * 60)))

    let value = try await coordinator.bearerToken()

    XCTAssertEqual(value, "fresh-boundary")
    XCTAssertEqual(client.refreshCallCount, 1)
  }

  func testBearerToken_usesTokenJustOutsideRefreshBoundary() async throws {
    persistence.savedToken = token("still-valid", expiresIn: 91)

    let value = try await coordinator.bearerToken()

    XCTAssertEqual(value, "still-valid")
    XCTAssertEqual(client.refreshCallCount, 0)
  }

  func testBearerToken_refreshesExpiredToken() async throws {
    persistence.savedToken = token("expired", expiresIn: -1)
    client.enqueue(.success(token("fresh", expiresIn: 10 * 60)))

    let value = try await coordinator.bearerToken()

    XCTAssertEqual(value, "fresh")
    XCTAssertEqual(client.refreshCallCount, 1)
  }

  func testBearerToken_singleFlightsConcurrentRefreshes() async throws {
    persistence.savedToken = token("stale", expiresIn: 5)
    client.enqueueDelayedSuccess(token("single-flight", expiresIn: 10 * 60))

    async let first = coordinator.bearerToken()
    async let second = coordinator.bearerToken()
    async let third = coordinator.bearerToken()

    try await waitUntil { await self.client.refreshCallCount == 1 }
    await client.releaseDelayedRefresh()

    let values = try await [first, second, third]
    XCTAssertEqual(values, ["single-flight", "single-flight", "single-flight"])
    XCTAssertEqual(client.refreshCallCount, 1)
  }

  func testRefreshFailureSurfacesReauthAndClearsPersistedToken() async {
    persistence.savedToken = token("expired", expiresIn: -1)
    client.enqueue(.failure(TestRefreshError.network))

    do {
      _ = try await coordinator.bearerToken()
      XCTFail("Expected refresh to throw")
    } catch {
      XCTAssertEqual(error as? TestRefreshError, .network)
    }

    let needsReauth = await coordinator.isReauthRequired()
    XCTAssertTrue(needsReauth)
    XCTAssertNil(persistence.savedToken)
    XCTAssertEqual(client.refreshCallCount, 1)
  }

  func testRefreshAfterUnauthorizedDoesNotUseCachedToken() async throws {
    persistence.savedToken = token("cached", expiresIn: 10 * 60)
    client.enqueue(.success(token("after-401", expiresIn: 10 * 60)))

    let value = try await coordinator.refreshAfterUnauthorized()

    XCTAssertEqual(value, "after-401")
    XCTAssertEqual(client.refreshCallCount, 1)
    XCTAssertEqual(persistence.savedToken?.value, "after-401")
  }

  func testUnauthorizedRefreshFailureMarksReauthRequired() async {
    persistence.savedToken = token("cached", expiresIn: 10 * 60)
    client.enqueue(.failure(TestRefreshError.unauthorized))

    do {
      _ = try await coordinator.refreshAfterUnauthorized()
      XCTFail("Expected unauthorized refresh failure")
    } catch {
      XCTAssertEqual(error as? TestRefreshError, .unauthorized)
    }

    let needsReauth = await coordinator.isReauthRequired()
    XCTAssertTrue(needsReauth)
    XCTAssertNil(persistence.savedToken)
  }

  func testAuthRestoredBySuccessfulRefreshClearsPriorReauthState() async throws {
    await coordinator.markReauthRequired()
    client.enqueue(.success(token("restored", expiresIn: 10 * 60)))

    let value = try await coordinator.bearerToken()

    XCTAssertEqual(value, "restored")
    let needsReauth = await coordinator.isReauthRequired()
    XCTAssertFalse(needsReauth)
  }

  func testPersistedTokenRestoresAcrossColdStart() async throws {
    persistence.savedToken = token("persisted", expiresIn: 10 * 60)
    let coldStartCoordinator = makeCoordinator()

    let restored = await coldStartCoordinator.restorePersistedToken()
    let value = try await coldStartCoordinator.bearerToken()

    XCTAssertEqual(restored?.value, "persisted")
    XCTAssertEqual(value, "persisted")
    XCTAssertEqual(client.refreshCallCount, 0)
  }

  func testForegroundUsesPersistedTokenWhenStillFresh() async throws {
    persistence.savedToken = token("foreground", expiresIn: 10 * 60)

    let value = try await coordinator.tokenAfterForeground()

    XCTAssertEqual(value, "foreground")
    XCTAssertEqual(client.refreshCallCount, 0)
  }

  func testForegroundRefreshesPersistedTokenWhenNearExpiry() async throws {
    persistence.savedToken = token("foreground-stale", expiresIn: 30)
    client.enqueue(.success(token("foreground-fresh", expiresIn: 10 * 60)))

    let value = try await coordinator.tokenAfterForeground()

    XCTAssertEqual(value, "foreground-fresh")
    XCTAssertEqual(client.refreshCallCount, 1)
  }

  func testNoInfiniteLoopOnChainedUnauthorizedRefreshesProperty() async {
    for unauthorizedCount in 1...25 {
      client = MockClerkTokenRefreshClient()
      persistence = InMemoryClerkTokenPersistence()
      coordinator = makeCoordinator()
      persistence.savedToken = token("cached-\(unauthorizedCount)", expiresIn: 10 * 60)
      for _ in 0..<unauthorizedCount {
        client.enqueue(.failure(TestRefreshError.unauthorized))
      }

      do {
        _ = try await coordinator.refreshAfterUnauthorized()
        XCTFail("Expected unauthorized refresh failure for count \(unauthorizedCount)")
      } catch {
        XCTAssertEqual(error as? TestRefreshError, .unauthorized)
      }

      XCTAssertEqual(
        client.refreshCallCount,
        1,
        "Refresh should attempt once per 401 handling pass, not loop through queued 401s"
      )
      let needsReauth = await coordinator.isReauthRequired()
      XCTAssertTrue(needsReauth)
    }
  }

  func testMarkReauthRequiredClearsPersistedToken() async {
    persistence.savedToken = token("cached", expiresIn: 10 * 60)

    await coordinator.markReauthRequired()

    let needsReauth = await coordinator.isReauthRequired()
    XCTAssertTrue(needsReauth)
    XCTAssertNil(persistence.savedToken)
  }

  // MARK: - AMA-436: SecureStorageProviding / KeychainClerkTokenPersistence

  func testSecureStoragePersistenceRoundTripsToken() {
    let persistence = KeychainClerkTokenPersistence(
      storage: MockSecureStorage(),
      legacyDefaults: nil,
      legacyKey: nil
    )

    XCTAssertNil(persistence.loadClerkToken(), "starts empty")

    let saved = ClerkAuthToken(value: "kc-token", expiresAt: now.addingTimeInterval(600))
    persistence.saveClerkToken(saved)

    XCTAssertEqual(persistence.loadClerkToken(), saved)
  }

  func testSecureStoragePersistenceOverwritesExistingToken() {
    let persistence = KeychainClerkTokenPersistence(
      storage: MockSecureStorage(),
      legacyDefaults: nil,
      legacyKey: nil
    )

    let first = ClerkAuthToken(value: "first", expiresAt: now.addingTimeInterval(60))
    let second = ClerkAuthToken(value: "second", expiresAt: now.addingTimeInterval(600))
    persistence.saveClerkToken(first)
    persistence.saveClerkToken(second)

    XCTAssertEqual(persistence.loadClerkToken(), second,
                   "save must overwrite the prior token")
  }

  func testSecureStoragePersistenceClearRemovesToken() {
    let persistence = KeychainClerkTokenPersistence(
      storage: MockSecureStorage(),
      legacyDefaults: nil,
      legacyKey: nil
    )
    persistence.saveClerkToken(
      ClerkAuthToken(value: "x", expiresAt: now.addingTimeInterval(60)))
    XCTAssertNotNil(persistence.loadClerkToken())

    persistence.clearClerkToken()

    XCTAssertNil(persistence.loadClerkToken())
  }

  func testSecureStoragePersistenceMigratesFromUserDefaultsOnFirstRead() {
    // Simulate the legacy state: a prior install wrote the token into
    // UserDefaults. New install should pick it up, copy to secure storage,
    // and wipe the UserDefaults entry so subsequent reads bypass migration.
    let suiteName = "ClerkTokenRefreshTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let legacyKey = "legacy_clerk_token"
    let legacyToken = ClerkAuthToken(value: "legacy", expiresAt: now.addingTimeInterval(600))
    defaults.set(try! JSONEncoder().encode(legacyToken), forKey: legacyKey)

    let persistence = KeychainClerkTokenPersistence(
      storage: MockSecureStorage(),
      legacyDefaults: defaults,
      legacyKey: legacyKey
    )

    let migrated = persistence.loadClerkToken()
    XCTAssertEqual(migrated, legacyToken, "first read must migrate")
    XCTAssertNil(defaults.data(forKey: legacyKey),
                 "legacy entry must be wiped after migration")

    let secondRead = persistence.loadClerkToken()
    XCTAssertEqual(secondRead, legacyToken)
  }

  func testSecureStoragePersistenceClearAlsoWipesLegacyDefaults() {
    let suiteName = "ClerkTokenRefreshTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let legacyKey = "legacy_clerk_token"
    defaults.set(Data([0x01]), forKey: legacyKey)

    let persistence = KeychainClerkTokenPersistence(
      storage: MockSecureStorage(),
      legacyDefaults: defaults,
      legacyKey: legacyKey
    )

    persistence.clearClerkToken()

    XCTAssertNil(defaults.data(forKey: legacyKey),
                 "clear must defensively wipe legacy storage too")
  }

  // MARK: - AMA-298: shared container mirroring

  func testSecureStoragePersistenceSaveTokenMirrorsToSharedContainer() {
    let suiteName = "ClerkTokenRefreshTests.SharedContainer.\(UUID().uuidString)"
    let sharedDefaults = UserDefaults(suiteName: suiteName)!
    defer { sharedDefaults.removePersistentDomain(forName: suiteName) }

    let persistence = KeychainClerkTokenPersistence(
      storage: MockSecureStorage(),
      legacyDefaults: nil,
      legacyKey: nil,
      sharedDefaults: sharedDefaults,
      sharedDefaultsTokenKey: "auth_token"
    )

    let saved = ClerkAuthToken(value: "share-ext-bearer", expiresAt: now.addingTimeInterval(600))
    persistence.saveClerkToken(saved)

    XCTAssertEqual(sharedDefaults.string(forKey: "auth_token"), "share-ext-bearer",
                   "raw JWT value must be mirrored to shared container for share extension")
  }

  func testSecureStoragePersistenceClearTokenRemovesSharedContainerEntry() {
    let suiteName = "ClerkTokenRefreshTests.SharedContainer.\(UUID().uuidString)"
    let sharedDefaults = UserDefaults(suiteName: suiteName)!
    defer { sharedDefaults.removePersistentDomain(forName: suiteName) }

    let persistence = KeychainClerkTokenPersistence(
      storage: MockSecureStorage(),
      legacyDefaults: nil,
      legacyKey: nil,
      sharedDefaults: sharedDefaults,
      sharedDefaultsTokenKey: "auth_token"
    )
    persistence.saveClerkToken(
      ClerkAuthToken(value: "token-to-clear", expiresAt: now.addingTimeInterval(600)))
    XCTAssertNotNil(sharedDefaults.string(forKey: "auth_token"), "token must be present before clear")

    persistence.clearClerkToken()

    XCTAssertNil(sharedDefaults.string(forKey: "auth_token"),
                 "shared container auth_token must be removed on clear")
  }

  func testSecureStoragePersistenceOverwriteUpdatesSharedContainer() {
    let suiteName = "ClerkTokenRefreshTests.SharedContainer.\(UUID().uuidString)"
    let sharedDefaults = UserDefaults(suiteName: suiteName)!
    defer { sharedDefaults.removePersistentDomain(forName: suiteName) }

    let persistence = KeychainClerkTokenPersistence(
      storage: MockSecureStorage(),
      legacyDefaults: nil,
      legacyKey: nil,
      sharedDefaults: sharedDefaults,
      sharedDefaultsTokenKey: "auth_token"
    )

    persistence.saveClerkToken(
      ClerkAuthToken(value: "first-token", expiresAt: now.addingTimeInterval(60)))
    persistence.saveClerkToken(
      ClerkAuthToken(value: "second-token", expiresAt: now.addingTimeInterval(600)))

    XCTAssertEqual(sharedDefaults.string(forKey: "auth_token"), "second-token",
                   "shared container must reflect the most-recently saved token")
  }

  // MARK: - AMA-1809: LiveSecureStorage (Keychain round-trip integration test)

  func testLiveSecureStorageRoundTripsToken() {
    let uniqueService = "ClerkTokenRefreshTests.\(UUID().uuidString)"
    let persistence = KeychainClerkTokenPersistence(
      storage: LiveSecureStorage(service: uniqueService),
      legacyDefaults: nil,
      legacyKey: nil
    )
    defer { persistence.clearClerkToken() }

    XCTAssertNil(persistence.loadClerkToken(), "starts empty")

    let saved = ClerkAuthToken(value: "live-kc-token", expiresAt: now.addingTimeInterval(600))
    persistence.saveClerkToken(saved)

    XCTAssertEqual(persistence.loadClerkToken(), saved)
  }

  private func makeCoordinator() -> ClerkTokenRefreshCoordinator {
    ClerkTokenRefreshCoordinator(
      client: client,
      persistence: persistence,
      refreshBeforeExpiry: 60,
      clockSkewTolerance: 30,
      now: { [now] in now! }
    )
  }

  private func token(_ value: String, expiresIn seconds: TimeInterval) -> ClerkAuthToken {
    ClerkAuthToken(value: value, expiresAt: now.addingTimeInterval(seconds))
  }

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @escaping () async -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
    while !(await predicate()) {
      if ContinuousClock.now >= deadline {
        XCTFail("Timed out waiting for condition", file: file, line: line)
        return
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
  }
}

private enum TestRefreshError: Error, Equatable {
  case network
  case unauthorized
}

private final class MockClerkTokenRefreshClient: ClerkTokenRefreshClient, @unchecked Sendable {
  private struct DelayedRefresh {
    let token: ClerkAuthToken
    let continuation: CheckedContinuation<ClerkAuthToken, Error>
  }

  private let lock = NSLock()
  private var queue: [(result: Result<ClerkAuthToken, Error>, delayed: Bool)] = []
  private var delayedRefresh: DelayedRefresh?
  private(set) var refreshCallCount = 0

  func enqueue(_ result: Result<ClerkAuthToken, Error>) {
    lock.withLock {
      queue.append((result, false))
    }
  }

  func enqueueDelayedSuccess(_ token: ClerkAuthToken) {
    lock.withLock {
      queue.append((.success(token), true))
    }
  }

  func refreshClerkToken() async throws -> ClerkAuthToken {
    let item: (result: Result<ClerkAuthToken, Error>, delayed: Bool) = lock.withLock {
      refreshCallCount += 1
      return queue.isEmpty ? (.failure(TestRefreshError.network), false) : queue.removeFirst()
    }

    switch item.result {
    case .success(let token):
      if item.delayed {
        return try await withCheckedThrowingContinuation { continuation in
          lock.withLock {
            precondition(delayedRefresh == nil, "Only one delayed refresh is supported")
            delayedRefresh = DelayedRefresh(token: token, continuation: continuation)
          }
        }
      }
      return token
    case .failure(let error):
      throw error
    }
  }

  func releaseDelayedRefresh() {
    let pending = lock.withLock { () -> DelayedRefresh? in
      defer { delayedRefresh = nil }
      return delayedRefresh
    }
    pending?.continuation.resume(returning: pending!.token)
  }
}

private final class InMemoryClerkTokenPersistence: ClerkTokenPersistence, @unchecked Sendable {
  private let lock = NSLock()
  private var token: ClerkAuthToken?

  var savedToken: ClerkAuthToken? {
    get { lock.withLock { token } }
    set { lock.withLock { token = newValue } }
  }

  func loadClerkToken() -> ClerkAuthToken? {
    savedToken
  }

  func saveClerkToken(_ token: ClerkAuthToken) {
    savedToken = token
  }

  func clearClerkToken() {
    savedToken = nil
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
