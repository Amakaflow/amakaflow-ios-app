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

  func testUserDefaultsPersistenceRoundTripsToken() {
    let suiteName = "ClerkTokenRefreshTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsClerkTokenPersistence(
      userDefaults: defaults, key: "test_clerk_token")
    let saved = ClerkAuthToken(value: "persisted-token", expiresAt: now.addingTimeInterval(600))

    persistence.saveClerkToken(saved)
    let loaded = persistence.loadClerkToken()
    persistence.clearClerkToken()

    XCTAssertEqual(loaded, saved)
    XCTAssertNil(persistence.loadClerkToken())
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
