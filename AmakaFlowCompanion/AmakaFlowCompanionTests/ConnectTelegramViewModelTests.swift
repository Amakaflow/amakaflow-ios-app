import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class ConnectTelegramViewModelTests: XCTestCase {
  private var api: MockTelegramAPIService!
  private var opener: MockURLOpener!
  private var now: Date!
  private var connectedIds: [Int?]!

  override func setUp() {
    super.setUp()
    api = MockTelegramAPIService()
    opener = MockURLOpener()
    now = Date(timeIntervalSince1970: 1_700_000_000)
    connectedIds = []
  }

  override func tearDown() {
    connectedIds = nil
    now = nil
    opener = nil
    api = nil
    super.tearDown()
  }

  func testConnectTapped_mintsTokenOpensNativeTelegramAndPollsUntilLinked() async throws {
    api.tokenResponse = tokenResponse()
    api.statusResponses = [
      TelegramLinkStatusResponse(linked: false, telegramId: nil, usedAt: nil),
      TelegramLinkStatusResponse(linked: true, telegramId: 42, usedAt: now),
    ]
    let viewModel = makeViewModel(pollIntervalNanoseconds: 1)

    viewModel.connectTapped()

    try await waitUntil { viewModel.state == .connected(telegramId: 42) }
    XCTAssertEqual(api.mintCallCount, 1)
    XCTAssertEqual(api.statusTokens, ["token-1", "token-1"])
    XCTAssertEqual(opener.openedURLs.map(\.absoluteString), ["tg://resolve?domain=amakaflow_userbot&start=token-1"])
    XCTAssertEqual(connectedIds, [42])
  }

  func testConnectTapped_fallsBackToDeepLinkWhenNativeTelegramDoesNotOpen() async throws {
    api.tokenResponse = tokenResponse()
    api.statusResponses = [TelegramLinkStatusResponse(linked: true, telegramId: 123, usedAt: now)]
    opener.results = [false, true]
    let viewModel = makeViewModel(pollIntervalNanoseconds: 1)

    viewModel.connectTapped()

    try await waitUntil { viewModel.state == .connected(telegramId: 123) }
    XCTAssertEqual(
      opener.openedURLs.map(\.absoluteString),
      [
        "tg://resolve?domain=amakaflow_userbot&start=token-1",
        "https://t.me/amakaflow_userbot?start=token-1",
      ]
    )
  }

  func testCancelStopsPollingAndReturnsToIdle() async throws {
    api.tokenResponse = tokenResponse()
    api.statusResponses = Array(
      repeating: TelegramLinkStatusResponse(linked: false, telegramId: nil, usedAt: nil),
      count: 10
    )
    let viewModel = makeViewModel(pollIntervalNanoseconds: 50_000_000)

    viewModel.connectTapped()
    try await waitUntil { viewModel.state == .connecting }

    viewModel.cancel()
    let callsAfterCancel = api.statusCallCount
    try await Task.sleep(nanoseconds: 120_000_000)

    XCTAssertEqual(viewModel.state, .idle)
    XCTAssertEqual(api.statusCallCount, callsAfterCancel)
  }

  func testTimeoutShowsRetryableError() async throws {
    api.tokenResponse = tokenResponse(expiresInSeconds: 900)
    api.statusResponses = Array(
      repeating: TelegramLinkStatusResponse(linked: false, telegramId: nil, usedAt: nil),
      count: 10
    )
    let viewModel = makeViewModel(pollIntervalNanoseconds: 1, timeoutSeconds: 0.01)

    viewModel.connectTapped()

    try await waitUntil {
      if case .failed("Timed out waiting for Telegram. Try again.") = viewModel.state { return true }
      return false
    }
  }

  func testTokenExpiryShowsFriendlyExpiredMessage() async throws {
    api.tokenResponse = tokenResponse(expiresInSeconds: 0)
    let viewModel = makeViewModel(pollIntervalNanoseconds: 1, timeoutSeconds: 90)

    viewModel.connectTapped()

    try await waitUntil {
      if case .failed("Link expired, try again.") = viewModel.state { return true }
      return false
    }
    XCTAssertEqual(api.statusCallCount, 0)
  }

  func testAlreadyConnectedRetapShowsNoOpMessage() {
    let viewModel = makeViewModel(initialTelegramId: 987)

    viewModel.connectTapped()

    XCTAssertEqual(
      viewModel.state,
      .failed("Telegram is already connected. Disconnect in Telegram if you want to switch accounts.")
    )
    XCTAssertEqual(api.mintCallCount, 0)
  }

  private func makeViewModel(
    initialTelegramId: Int? = nil,
    pollIntervalNanoseconds: UInt64 = 1,
    timeoutSeconds: TimeInterval = 90
  ) -> ConnectTelegramViewModel {
    ConnectTelegramViewModel(
      apiService: api,
      urlOpener: opener,
      initialTelegramId: initialTelegramId,
      pollIntervalNanoseconds: pollIntervalNanoseconds,
      timeoutSeconds: timeoutSeconds,
      now: { [now] in now! },
      onConnected: { self.connectedIds.append($0) }
    )
  }

  private func tokenResponse(expiresInSeconds: Int = 900) -> TelegramLinkTokenResponse {
    TelegramLinkTokenResponse(
      token: "token-1",
      deepLink: "https://t.me/amakaflow_userbot?start=token-1",
      nativeLink: "tg://resolve?domain=amakaflow_userbot&start=token-1",
      expiresInSeconds: expiresInSeconds
    )
  }

  private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () async -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for condition")
  }
}

@MainActor
private final class MockURLOpener: URLOpener {
  var results: [Bool] = [true]
  private(set) var openedURLs: [URL] = []

  func open(_ url: URL) async -> Bool {
    openedURLs.append(url)
    if results.count > 1 {
      return results.removeFirst()
    }
    return results.first ?? true
  }
}

private final class MockTelegramAPIService: TelegramLinkAPIProviding {
  var tokenResponse: TelegramLinkTokenResponse?
  var tokenError: Error?
  var statusResponses: [TelegramLinkStatusResponse] = []
  var statusError: Error?
  private(set) var mintCallCount = 0
  private(set) var statusCallCount = 0
  private(set) var statusTokens: [String] = []

  func mintTelegramLinkToken() async throws -> TelegramLinkTokenResponse {
    mintCallCount += 1
    if let tokenError { throw tokenError }
    return tokenResponse!
  }

  func getTelegramLinkStatus(token: String) async throws -> TelegramLinkStatusResponse {
    statusCallCount += 1
    statusTokens.append(token)
    if let statusError { throw statusError }
    if statusResponses.count > 1 {
      return statusResponses.removeFirst()
    }
    return statusResponses.first ?? TelegramLinkStatusResponse(linked: false, telegramId: nil, usedAt: nil)
  }
}
