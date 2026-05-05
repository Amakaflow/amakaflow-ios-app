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

private final class MockTelegramAPIService: APIServiceProviding {
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

  func fetchWorkouts(isRetry: Bool) async throws -> [Workout] { throw APIError.notImplemented }
  func fetchScheduledWorkouts(isRetry: Bool) async throws -> [ScheduledWorkout] { throw APIError.notImplemented }
  func fetchPushedWorkouts(isRetry: Bool) async throws -> [Workout] { throw APIError.notImplemented }
  func fetchPendingWorkouts(isRetry: Bool) async throws -> [Workout] { throw APIError.notImplemented }
  func syncWorkout(_ workout: Workout) async throws { throw APIError.notImplemented }
  func getAppleExport(workoutId: String) async throws -> String { throw APIError.notImplemented }
  func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport?) async throws -> VoiceWorkoutParseResponse { throw APIError.notImplemented }
  func ingestInstagramReel(url: String) async throws -> IngestInstagramReelResponse { throw APIError.notImplemented }
  func ingestText(text: String, source: String?) async throws -> IngestTextResponse { throw APIError.notImplemented }
  func transcribeAudio(audioData: String, provider: String, language: String, keywords: [String], includeWordTimings: Bool) async throws -> CloudTranscriptionResponse { throw APIError.notImplemented }
  func syncPersonalDictionary(corrections: [String: String], customTerms: [String]) async throws -> PersonalDictionaryResponse { throw APIError.notImplemented }
  func fetchPersonalDictionary() async throws -> PersonalDictionaryResponse { throw APIError.notImplemented }
  func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws { throw APIError.notImplemented }
  func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool) async throws -> WorkoutCompletionResponse { throw APIError.notImplemented }
  func confirmSync(workoutId: String, deviceType: String, deviceId: String?) async throws { throw APIError.notImplemented }
  func reportSyncFailed(workoutId: String, deviceType: String, error: String, deviceId: String?) async throws { throw APIError.notImplemented }
  func fetchProfile() async throws -> UserProfile { throw APIError.notImplemented }
  func fetchCompletions(limit: Int, offset: Int) async throws -> [WorkoutCompletion] { throw APIError.notImplemented }
  func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail { throw APIError.notImplemented }
  func fetchDayStates(from: String, to: String) async throws -> [DayState] { throw APIError.notImplemented }
  func generateWeek(request: GenerateWeekRequest?) async throws -> ProposedPlan { throw APIError.notImplemented }
  func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict] { throw APIError.notImplemented }
  func parseWorkoutText(text: String, context: String?) async throws -> ParsedWorkout { throw APIError.notImplemented }
  func fetchPendingActions() async throws -> [PendingAction] { throw APIError.notImplemented }
  func respondToAction(id: String, response: String) async throws -> ActionResponse { throw APIError.notImplemented }
  func sendCoachMessage(message: String, context: CoachContext?) async throws -> CoachResponse { throw APIError.notImplemented }
  func getFatigueAdvice(fatigueScore: Double?, loadHistory: [DailyLoad]?) async throws -> FatigueAdvice { throw APIError.notImplemented }
  func fetchCoachMemories() async throws -> [CoachMemory] { throw APIError.notImplemented }
  func fetchSocialFeed(cursor: String?, limit: Int) async throws -> FeedResponse { throw APIError.notImplemented }
  func addSocialReaction(postId: String, emoji: String) async throws { throw APIError.notImplemented }
  func removeSocialReaction(postId: String, emoji: String) async throws { throw APIError.notImplemented }
  func fetchSocialComments(postId: String) async throws -> CommentsResponse { throw APIError.notImplemented }
  func postSocialComment(postId: String, text: String) async throws { throw APIError.notImplemented }
  func fetchSocialSettings() async throws -> SocialSettings { throw APIError.notImplemented }
  func updateSocialSettings(_ settings: SocialSettings) async throws { throw APIError.notImplemented }
  func fetchUserPublicProfile(userId: String) async throws -> UserPublicProfile { throw APIError.notImplemented }
  func followUser(userId: String) async throws { throw APIError.notImplemented }
  func unfollowUser(userId: String) async throws { throw APIError.notImplemented }
  func fetchChallenges() async throws -> ChallengesResponse { throw APIError.notImplemented }
  func fetchChallengeDetail(id: String) async throws -> ChallengeDetailResponse { throw APIError.notImplemented }
  func createChallenge(_ request: CreateChallengeRequest) async throws { throw APIError.notImplemented }
  func joinChallenge(id: String) async throws { throw APIError.notImplemented }
  func fetchMyCrews() async throws -> CrewListResponse { throw APIError.notImplemented }
  func fetchCrewDetail(id: String) async throws -> CrewDetail { throw APIError.notImplemented }
  func fetchCrewFeed(crewId: String) async throws -> CrewFeedResponse { throw APIError.notImplemented }
  func createCrew(_ request: CreateCrewRequest) async throws { throw APIError.notImplemented }
  func joinCrew(crewId: String, request: JoinCrewRequest) async throws { throw APIError.notImplemented }
  func leaveCrew(crewId: String) async throws { throw APIError.notImplemented }
  func fetchFriendsLeaderboard(dimension: String, period: String) async throws -> LeaderboardAPIResponse { throw APIError.notImplemented }
  func fetchCrewLeaderboard(crewId: String, dimension: String, period: String) async throws -> LeaderboardAPIResponse { throw APIError.notImplemented }
  func saveWorkout(_ request: WorkoutSaveRequest) async throws -> Workout { throw APIError.notImplemented }
  func fetchConnectedCalendars() async throws -> [ConnectedCalendar] { throw APIError.notImplemented }
  func connectCalendar(provider: String) async throws -> String { throw APIError.notImplemented }
  func syncCalendar(calendarId: String) async throws -> CalendarSyncResponse { throw APIError.notImplemented }
  func disconnectCalendar(calendarId: String) async throws { throw APIError.notImplemented }
  func fetchShoeComparison() async throws -> [ShoeStats] { throw APIError.notImplemented }
  func fetchSubscription() async throws -> Subscription { throw APIError.notImplemented }
  func fetchNotificationPreferences() async throws -> NotificationPreferences { throw APIError.notImplemented }
  func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences { throw APIError.notImplemented }
  func analyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse { throw APIError.notImplemented }
  func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse { throw APIError.notImplemented }
  func parseText(text: String) async throws -> ParseTextAPIResponse { throw APIError.notImplemented }
  func getFuelingStatus() async throws -> FuelingStatusResponse { throw APIError.notImplemented }
  func checkProteinNudge() async throws -> ProteinNudgeResponse { throw APIError.notImplemented }
  func suggestWorkout(request: SuggestWorkoutRequest) async throws -> SuggestWorkoutResponse { throw APIError.notImplemented }
  func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse { throw APIError.notImplemented }
  func generateProgram(request: ProgramGenerationRequest) async throws -> ProgramGenerationResponse { throw APIError.notImplemented }
  func fetchGenerationStatus(jobId: String) async throws -> ProgramGenerationStatus { throw APIError.notImplemented }
  func updateProgramStatus(id: String, status: String) async throws { throw APIError.notImplemented }
  func updateProgramProgress(id: String, currentWeek: Int) async throws { throw APIError.notImplemented }
  func deleteProgram(id: String) async throws { throw APIError.notImplemented }
  func completeWorkout(workoutId: String) async throws { throw APIError.notImplemented }
  func fetchVolumeAnalytics(startDate: String, endDate: String, granularity: String) async throws -> VolumeAnalyticsResponse { throw APIError.notImplemented }
  func detectImport(request: BulkDetectRequest) async throws -> BulkDetectResponse { throw APIError.notImplemented }
  func matchExercises(request: BulkMatchRequest) async throws -> BulkMatchResponse { throw APIError.notImplemented }
  func previewImport(request: BulkPreviewRequest) async throws -> BulkPreviewResponse { throw APIError.notImplemented }
  func executeImport(request: BulkExecuteRequest) async throws -> BulkExecuteResponse { throw APIError.notImplemented }
  func fetchImportStatus(jobId: String, profileId: String) async throws -> BulkImportStatus { throw APIError.notImplemented }
  func cancelImport(jobId: String, profileId: String) async throws { throw APIError.notImplemented }

}
