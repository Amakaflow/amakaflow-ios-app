//
//  AppDependencies.swift
//  AmakaFlow
//
//  Dependency container for managing service instances throughout the app.
//  Enables dependency injection for testability and modularity.
//

import Foundation
import Combine
import WatchConnectivity

/// Container for all app dependencies
/// Use `.live` for production and `.mock` for testing
struct AppDependencies {
    let apiService: APIServiceProviding
    let pairingService: PairingServiceProviding
    let audioService: AudioProviding
    let progressStore: ProgressStoreProviding
    let watchSession: WatchSessionProviding

    /// Live dependencies using real service implementations
    @MainActor
    static let live = AppDependencies(
        apiService: APIService.shared,
        pairingService: PairingService.shared,
        audioService: AudioCueManager(),
        progressStore: LiveProgressStore.shared,
        watchSession: LiveWatchSession.shared
    )

    /// Mock dependencies for unit testing
    @MainActor
    static let mock = AppDependencies(
        apiService: MockAPIService(),
        pairingService: MockPairingService(),
        audioService: MockAudioService(),
        progressStore: MockProgressStore(),
        watchSession: MockWatchSession()
    )

    #if DEBUG
    /// Fixture dependencies for E2E testing with JSON fixture data
    /// Uses FixtureAPIService (bundled JSON, canned writes) with real UI services
    /// Watch session uses MockWatchSession to avoid WCSession permission modal (AMA-549)
    @MainActor
    static let fixture = AppDependencies(
        apiService: FixtureAPIService(),
        pairingService: PairingService.shared,
        audioService: AudioCueManager(),
        progressStore: LiveProgressStore.shared,
        watchSession: MockWatchSession()
    )

    /// Returns the appropriate dependencies based on environment:
    /// - `.fixture` when UITEST_USE_FIXTURES=true
    /// - `.live` otherwise
    @MainActor
    static var current: AppDependencies {
        if TestAuthStore.shared.useFixtures {
            return .fixture
        }
        return .live
    }
    #else
    @MainActor
    static var current: AppDependencies { .live }
    #endif
}

// MARK: - Mock Implementations

/// Mock API service for testing
class MockAPIService: APIServiceProviding {
    // MARK: - Configurable Results

    var fetchWorkoutsResult: Result<[Workout], Error> = .success([])
    var fetchScheduledWorkoutsResult: Result<[ScheduledWorkout], Error> = .success([])
    var fetchPushedWorkoutsResult: Result<[Workout], Error> = .success([])
    var fetchPendingWorkoutsResult: Result<[Workout], Error> = .success([])
    var syncWorkoutResult: Result<Void, Error> = .success(())
    var getAppleExportResult: Result<String, Error> = .success("{}")
    var parseVoiceWorkoutResult: Result<VoiceWorkoutParseResponse, Error>?
    var ingestInstagramReelResult: Result<IngestInstagramReelResponse, Error>?
    var ingestTextResult: Result<IngestTextResponse, Error>?
    var transcribeAudioResult: Result<CloudTranscriptionResponse, Error>?
    var syncPersonalDictionaryResult: Result<PersonalDictionaryResponse, Error> = .success(PersonalDictionaryResponse(corrections: [:], customTerms: []))
    var fetchPersonalDictionaryResult: Result<PersonalDictionaryResponse, Error> = .success(PersonalDictionaryResponse(corrections: [:], customTerms: []))
    var logManualWorkoutResult: Result<Void, Error> = .success(())
    var postWorkoutCompletionResult: Result<WorkoutCompletionResponse, Error>?
    var confirmSyncResult: Result<Void, Error> = .success(())
    var reportSyncFailedResult: Result<Void, Error> = .success(())
    var fetchProfileResult: Result<UserProfile, Error>?

    // MARK: - Call Tracking

    var fetchWorkoutsCalled = false
    var fetchScheduledWorkoutsCalled = false
    var fetchPushedWorkoutsCalled = false
    var fetchPendingWorkoutsCalled = false
    var syncWorkoutCalled = false
    var syncedWorkout: Workout?
    var getAppleExportCalled = false
    var parseVoiceWorkoutCalled = false
    var ingestInstagramReelCalled = false
    var ingestTextCalled = false
    var transcribeAudioCalled = false
    var syncPersonalDictionaryCalled = false
    var fetchPersonalDictionaryCalled = false
    var logManualWorkoutCalled = false
    var postWorkoutCompletionCalled = false
    var postedCompletion: WorkoutCompletionRequest?
    var confirmSyncCalled = false
    var confirmedWorkoutId: String?
    var reportSyncFailedCalled = false
    var fetchProfileCalled = false
    var fetchCompletionsCalled = false
    var fetchCompletionsResult: Result<[WorkoutCompletion], Error> = .success([])
    var fetchCompletionDetailCalled = false
    var fetchCompletionDetailResult: Result<WorkoutCompletionDetail, Error>?

    // MARK: - Protocol Implementation

    func fetchWorkouts(isRetry: Bool) async throws -> [Workout] {
        fetchWorkoutsCalled = true
        return try fetchWorkoutsResult.get()
    }

    func fetchScheduledWorkouts(isRetry: Bool) async throws -> [ScheduledWorkout] {
        fetchScheduledWorkoutsCalled = true
        return try fetchScheduledWorkoutsResult.get()
    }

    func fetchPushedWorkouts(isRetry: Bool) async throws -> [Workout] {
        fetchPushedWorkoutsCalled = true
        return try fetchPushedWorkoutsResult.get()
    }

    func fetchPendingWorkouts(isRetry: Bool) async throws -> [Workout] {
        fetchPendingWorkoutsCalled = true
        return try fetchPendingWorkoutsResult.get()
    }

    func syncWorkout(_ workout: Workout) async throws {
        syncWorkoutCalled = true
        syncedWorkout = workout
        try syncWorkoutResult.get()
    }

    func getAppleExport(workoutId: String) async throws -> String {
        getAppleExportCalled = true
        return try getAppleExportResult.get()
    }

    func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport?) async throws -> VoiceWorkoutParseResponse {
        parseVoiceWorkoutCalled = true
        guard let result = parseVoiceWorkoutResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func ingestInstagramReel(url: String) async throws -> IngestInstagramReelResponse {
        ingestInstagramReelCalled = true
        guard let result = ingestInstagramReelResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func ingestText(text: String, source: String?) async throws -> IngestTextResponse {
        ingestTextCalled = true
        guard let result = ingestTextResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func transcribeAudio(
        audioData: String,
        provider: String,
        language: String,
        keywords: [String],
        includeWordTimings: Bool
    ) async throws -> CloudTranscriptionResponse {
        transcribeAudioCalled = true
        guard let result = transcribeAudioResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func syncPersonalDictionary(
        corrections: [String: String],
        customTerms: [String]
    ) async throws -> PersonalDictionaryResponse {
        syncPersonalDictionaryCalled = true
        return try syncPersonalDictionaryResult.get()
    }

    func fetchPersonalDictionary() async throws -> PersonalDictionaryResponse {
        fetchPersonalDictionaryCalled = true
        return try fetchPersonalDictionaryResult.get()
    }

    func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws {
        logManualWorkoutCalled = true
        try logManualWorkoutResult.get()
    }

    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool) async throws -> WorkoutCompletionResponse {
        postWorkoutCompletionCalled = true
        postedCompletion = completion
        guard let result = postWorkoutCompletionResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func confirmSync(workoutId: String, deviceType: String, deviceId: String?) async throws {
        confirmSyncCalled = true
        confirmedWorkoutId = workoutId
        try confirmSyncResult.get()
    }

    func reportSyncFailed(workoutId: String, deviceType: String, error: String, deviceId: String?) async throws {
        reportSyncFailedCalled = true
        try reportSyncFailedResult.get()
    }

    func fetchProfile() async throws -> UserProfile {
        fetchProfileCalled = true
        guard let result = fetchProfileResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func fetchCompletions(limit: Int, offset: Int) async throws -> [WorkoutCompletion] {
        fetchCompletionsCalled = true
        return try fetchCompletionsResult.get()
    }

    func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail {
        fetchCompletionDetailCalled = true
        guard let result = fetchCompletionDetailResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    // MARK: - Planning (AMA-1147)

    var fetchDayStatesResult: Result<[DayState], Error> = .success([])
    var fetchDayStatesCalled = false
    var generateWeekResult: Result<ProposedPlan, Error>?
    var generateWeekCalled = false
    var detectConflictsResult: Result<[Conflict], Error> = .success([])
    var detectConflictsCalled = false
    var parseWorkoutTextResult: Result<ParsedWorkout, Error>?
    var parseWorkoutTextCalled = false

    func fetchDayStates(from: String, to: String) async throws -> [DayState] {
        fetchDayStatesCalled = true
        return try fetchDayStatesResult.get()
    }

    func generateWeek(request: GenerateWeekRequest?) async throws -> ProposedPlan {
        generateWeekCalled = true
        guard let result = generateWeekResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict] {
        detectConflictsCalled = true
        return try detectConflictsResult.get()
    }

    func parseWorkoutText(text: String, context: String?) async throws -> ParsedWorkout {
        parseWorkoutTextCalled = true
        guard let result = parseWorkoutTextResult else { throw APIError.notImplemented }
        return try result.get()
    }

    // MARK: - Actions (AMA-1147)

    var fetchPendingActionsResult: Result<[PendingAction], Error> = .success([])
    var fetchPendingActionsCalled = false
    var respondToActionResult: Result<ActionResponse, Error> = .success(ActionResponse(success: true, message: nil))
    var respondToActionCalled = false

    func fetchPendingActions() async throws -> [PendingAction] {
        fetchPendingActionsCalled = true
        return try fetchPendingActionsResult.get()
    }

    func respondToAction(id: String, response: String) async throws -> ActionResponse {
        respondToActionCalled = true
        return try respondToActionResult.get()
    }

    // MARK: - Coach (AMA-1147)

    var sendCoachMessageResult: Result<CoachResponse, Error>?
    var sendCoachMessageCalled = false
    var getFatigueAdviceResult: Result<FatigueAdvice, Error>?
    var getFatigueAdviceCalled = false
    var fetchCoachMemoriesResult: Result<[CoachMemory], Error> = .success([])
    var fetchCoachMemoriesCalled = false

    func sendCoachMessage(message: String, context: CoachContext?) async throws -> CoachResponse {
        sendCoachMessageCalled = true
        guard let result = sendCoachMessageResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func getFatigueAdvice(fatigueScore: Double?, loadHistory: [DailyLoad]?) async throws -> FatigueAdvice {
        getFatigueAdviceCalled = true
        guard let result = getFatigueAdviceResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func fetchCoachMemories() async throws -> [CoachMemory] {
        fetchCoachMemoriesCalled = true
        return try fetchCoachMemoriesResult.get()
    }

    // MARK: - Analytics (AMA-1147)

    var fetchShoeComparisonResult: Result<[ShoeStats], Error> = .success([])
    var fetchShoeComparisonCalled = false

    func fetchShoeComparison() async throws -> [ShoeStats] {
        fetchShoeComparisonCalled = true
        return try fetchShoeComparisonResult.get()
    }

    // MARK: - Billing (AMA-1147)

    var fetchSubscriptionResult: Result<Subscription, Error>?
    var fetchSubscriptionCalled = false

    func fetchSubscription() async throws -> Subscription {
        fetchSubscriptionCalled = true
        guard let result = fetchSubscriptionResult else { throw APIError.notImplemented }
        return try result.get()
    }

    // MARK: - Notification Preferences (AMA-1147)

    var fetchNotificationPreferencesResult: Result<NotificationPreferences, Error> = .success(NotificationPreferences())
    var fetchNotificationPreferencesCalled = false
    var updateNotificationPreferencesResult: Result<NotificationPreferences, Error> = .success(NotificationPreferences())
    var updateNotificationPreferencesCalled = false

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        fetchNotificationPreferencesCalled = true
        return try fetchNotificationPreferencesResult.get()
    }

    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences {
        updateNotificationPreferencesCalled = true
        return try updateNotificationPreferencesResult.get()
    }


    // MARK: - Workout Save (AMA-1231)

    var saveWorkoutCalled = false
    func saveWorkout(_ request: WorkoutSaveRequest) async throws -> Workout {
        saveWorkoutCalled = true
        throw APIError.notImplemented
    }

    // MARK: - Calendar Sync (AMA-1238)

    func fetchConnectedCalendars() async throws -> [ConnectedCalendar] { [] }
    func connectCalendar(provider: String) async throws -> String { "https://example.com/auth" }
    func syncCalendar(calendarId: String) async throws -> CalendarSyncResponse { CalendarSyncResponse(syncedEvents: 0) }
    func disconnectCalendar(calendarId: String) async throws {}

    // MARK: - Social Feed (AMA-1273)

    var fetchSocialFeedResult: Result<FeedResponse, Error> = .success(FeedResponse(posts: [], nextCursor: nil, hasMore: false))
    var addSocialReactionCalled = false
    var removeSocialReactionCalled = false
    var fetchSocialCommentsCalled = false
    var postSocialCommentCalled = false
    var fetchSocialSettingsResult: Result<SocialSettings, Error> = .success(.default)
    var updateSocialSettingsCalled = false
    var fetchUserPublicProfileResult: Result<UserPublicProfile, Error> = .failure(APIError.notImplemented)

    func fetchSocialFeed(cursor: String?, limit: Int) async throws -> FeedResponse {
        return try fetchSocialFeedResult.get()
    }

    func addSocialReaction(postId: String, emoji: String) async throws {
        addSocialReactionCalled = true
    }

    func removeSocialReaction(postId: String, emoji: String) async throws {
        removeSocialReactionCalled = true
    }

    func fetchSocialComments(postId: String) async throws -> CommentsResponse {
        fetchSocialCommentsCalled = true
        return CommentsResponse(comments: [])
    }

    func postSocialComment(postId: String, text: String) async throws {
        postSocialCommentCalled = true
    }

    func fetchSocialSettings() async throws -> SocialSettings {
        return try fetchSocialSettingsResult.get()
    }

    func updateSocialSettings(_ settings: SocialSettings) async throws {
        updateSocialSettingsCalled = true
    }

    func fetchUserPublicProfile(userId: String) async throws -> UserPublicProfile {
        return try fetchUserPublicProfileResult.get()
    }

    // MARK: - Challenges (AMA-1276)

    var fetchChallengesResult: Result<ChallengesResponse, Error> = .success(ChallengesResponse(challenges: []))
    var fetchChallengesCalled = false
    var fetchChallengeDetailResult: Result<ChallengeDetailResponse, Error>?
    var fetchChallengeDetailCalled = false
    var createChallengeCalled = false
    var joinChallengeCalled = false

    func fetchChallenges() async throws -> ChallengesResponse {
        fetchChallengesCalled = true
        return try fetchChallengesResult.get()
    }

    func fetchChallengeDetail(id: String) async throws -> ChallengeDetailResponse {
        fetchChallengeDetailCalled = true
        guard let result = fetchChallengeDetailResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func createChallenge(_ request: CreateChallengeRequest) async throws {
        createChallengeCalled = true
    }

    func joinChallenge(id: String) async throws {
        joinChallengeCalled = true
    }

    // MARK: - Training Crews (AMA-1277)

    func fetchMyCrews() async throws -> CrewListResponse {
        return CrewListResponse(crews: [], count: 0)
    }

    func fetchCrewDetail(id: String) async throws -> CrewDetail {
        throw APIError.notFound
    }

    func fetchCrewFeed(crewId: String) async throws -> CrewFeedResponse {
        return CrewFeedResponse(posts: [], nextCursor: nil)
    }

    func createCrew(_ request: CreateCrewRequest) async throws {}

    func joinCrew(crewId: String, request: JoinCrewRequest) async throws {}

    func leaveCrew(crewId: String) async throws {}

    // MARK: - Leaderboards (AMA-1278)

    func fetchFriendsLeaderboard(dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        LeaderboardAPIResponse(dimension: dimension, period: period, entries: [])
    }

    func fetchCrewLeaderboard(crewId: String, dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        LeaderboardAPIResponse(dimension: dimension, period: period, entries: [])
    }
}

/// Mock pairing service for testing
@MainActor
class MockPairingService: PairingServiceProviding {
    // MARK: - Published Properties

    @Published var isPaired: Bool = false
    @Published var userProfile: UserProfile?
    @Published var needsReauth: Bool = false
    var lastTokenRefresh: Date?

    // MARK: - Publishers

    var isPairedPublisher: Published<Bool>.Publisher { $isPaired }
    var userProfilePublisher: Published<UserProfile?>.Publisher { $userProfile }
    var needsReauthPublisher: Published<Bool>.Publisher { $needsReauth }

    // MARK: - Configurable Results

    var pairResult: Result<PairingResponse, Error>?
    var refreshTokenResult: Bool = false
    var storedToken: String?

    // MARK: - Call Tracking

    var markAuthInvalidCalled = false
    var authRestoredCalled = false
    var pairCalled = false
    var pairCode: String?
    var refreshTokenCalled = false
    var getTokenCalled = false
    var unpairCalled = false

    #if DEBUG
    var enableTestModeCalled = false
    var disableTestModeCalled = false
    var isInTestMode: Bool = false
    #endif

    // MARK: - Initialization

    /// Nonisolated init to allow creation from async test contexts
    nonisolated init() {}

    // MARK: - Protocol Implementation

    func markAuthInvalid() {
        markAuthInvalidCalled = true
        needsReauth = true
    }

    func authRestored() {
        authRestoredCalled = true
        needsReauth = false
    }

    func pair(code: String) async throws -> PairingResponse {
        pairCalled = true
        pairCode = code
        guard let result = pairResult else {
            throw PairingError.invalidCode("Mock not configured")
        }
        let response = try result.get()
        isPaired = true
        return response
    }

    func refreshToken() async -> Bool {
        refreshTokenCalled = true
        return refreshTokenResult
    }

    func getToken() -> String? {
        getTokenCalled = true
        return storedToken
    }

    func unpair() {
        unpairCalled = true
        isPaired = false
        userProfile = nil
        storedToken = nil
    }

    #if DEBUG
    func enableTestMode(authSecret: String, userId: String) {
        enableTestModeCalled = true
        isInTestMode = true
        isPaired = true
    }

    func disableTestMode() {
        disableTestModeCalled = true
        isInTestMode = false
        isPaired = false
    }
    #endif
}

/// Mock audio service for testing
class MockAudioService: AudioProviding {
    // MARK: - State

    var isEnabled: Bool = true
    var isSpeaking: Bool = false

    // MARK: - Call Tracking

    var speakCalled = false
    var lastSpokenText: String?
    var lastSpeechPriority: SpeechPriority?
    var stopSpeakingCalled = false
    var announceWorkoutStartCalled = false
    var announceStepCalled = false
    var announceCountdownCalled = false
    var announceWorkoutCompleteCalled = false
    var announcePausedCalled = false
    var announceResumedCalled = false
    var announceRestCalled = false

    // MARK: - Protocol Implementation

    func speak(_ text: String, priority: SpeechPriority) {
        speakCalled = true
        lastSpokenText = text
        lastSpeechPriority = priority
    }

    func stopSpeaking() {
        stopSpeakingCalled = true
        isSpeaking = false
    }

    func announceWorkoutStart(_ workoutName: String) {
        announceWorkoutStartCalled = true
        speak("Starting \(workoutName)", priority: .high)
    }

    func announceStep(_ stepName: String, roundInfo: String?) {
        announceStepCalled = true
        var announcement = stepName
        if let round = roundInfo {
            announcement = "\(round). \(stepName)"
        }
        speak(announcement, priority: .high)
    }

    func announceCountdown(_ seconds: Int) {
        announceCountdownCalled = true
        speak("\(seconds)", priority: .countdown)
    }

    func announceWorkoutComplete() {
        announceWorkoutCompleteCalled = true
        speak("Workout complete. Great job!", priority: .high)
    }

    func announcePaused() {
        announcePausedCalled = true
        speak("Paused", priority: .normal)
    }

    func announceResumed() {
        announceResumedCalled = true
        speak("Resuming", priority: .normal)
    }

    func announceRest(isManual: Bool, seconds: Int) {
        announceRestCalled = true
        if isManual {
            speak("Rest. Tap when ready.", priority: .high)
        } else if seconds > 0 {
            speak("Rest for \(seconds) seconds", priority: .high)
        }
    }
}

/// Mock progress store for testing
class MockProgressStore: ProgressStoreProviding {
    // MARK: - State

    var storedProgress: SavedWorkoutProgress?

    // MARK: - Call Tracking

    var saveCalled = false
    var loadCalled = false
    var clearCalled = false

    // MARK: - Protocol Implementation

    func save(_ progress: SavedWorkoutProgress) {
        saveCalled = true
        storedProgress = progress
    }

    func load() -> SavedWorkoutProgress? {
        loadCalled = true
        return storedProgress
    }

    func clear() {
        clearCalled = true
        storedProgress = nil
    }
}

/// Mock watch session for testing
class MockWatchSession: WatchSessionProviding {
    // MARK: - Configurable State

    var isWatchAppInstalled: Bool = true
    var isReachable: Bool = true
    var isPaired: Bool = true
    var activationState: WCSessionActivationState = .activated
    weak var delegate: WCSessionDelegate?

    // MARK: - Call Tracking

    var activateCalled = false
    var sendMessageCalled = false
    var sentMessages: [[String: Any]] = []
    var lastReplyHandler: (([String: Any]) -> Void)?
    var lastErrorHandler: ((Error) -> Void)?
    var transferUserInfoCalled = false
    var transferredUserInfo: [[String: Any]] = []
    var updateApplicationContextCalled = false
    var lastApplicationContext: [String: Any]?

    // MARK: - Configurable Behavior

    /// Error to trigger in errorHandler when sendMessage is called
    var sendMessageError: Error?

    /// Reply to return when sendMessage is called
    var sendMessageReply: [String: Any]?

    /// Error to throw when updateApplicationContext is called
    var updateContextError: Error?

    // MARK: - Protocol Implementation

    func activate() {
        activateCalled = true
    }

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    ) {
        sendMessageCalled = true
        sentMessages.append(message)
        lastReplyHandler = replyHandler
        lastErrorHandler = errorHandler

        // Simulate error if configured
        if let error = sendMessageError {
            errorHandler?(error)
        } else if let reply = sendMessageReply {
            replyHandler?(reply)
        }
    }

    @discardableResult
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer? {
        transferUserInfoCalled = true
        transferredUserInfo.append(userInfo)
        return nil  // Mock doesn't create real transfer objects
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        updateApplicationContextCalled = true
        lastApplicationContext = applicationContext
        if let error = updateContextError {
            throw error
        }
    }

    // MARK: - Test Helpers

    /// Simulate receiving a message from watch (calls delegate method)
    func simulateReceivedMessage(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // This would need a real WCSession to work, but for testing we can track the call
        // In a real test, you would call the delegate method directly on the manager
    }

    /// Reset all call tracking state
    func reset() {
        activateCalled = false
        sendMessageCalled = false
        sentMessages.removeAll()
        lastReplyHandler = nil
        lastErrorHandler = nil
        transferUserInfoCalled = false
        transferredUserInfo.removeAll()
        updateApplicationContextCalled = false
        lastApplicationContext = nil
    }
}
