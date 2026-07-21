//
//  MockAPIService.swift
//  AmakaFlowCompanionTests
//
//  Test-only API service double. Keep this out of the app target so it does not ship.
//

import Foundation
@testable import AmakaFlowCompanion

/// Mock API service for testing
class MockAPIService: APIServiceProviding {
    // MARK: - Configurable Results

    var fetchWorkoutsResult: Result<[Workout], Error> = .success([])
    var fetchScheduledWorkoutsResult: Result<[ScheduledWorkout], Error> = .success([])
    var fetchPushedWorkoutsResult: Result<[Workout], Error> = .success([])
    var fetchPendingWorkoutsResult: Result<[Workout], Error> = .success([])
    var syncWorkoutResult: Result<Void, Error> = .success(())
    var getAppleExportResult: Result<String, Error> = .success("{}")
    var mintTelegramLinkTokenResult: Result<TelegramLinkTokenResponse, Error> = .success(
        TelegramLinkTokenResponse(
            token: "mock-telegram-token",
            deepLink: "https://t.me/amakaflow_userbot?start=mock-telegram-token",
            nativeLink: "tg://resolve?domain=amakaflow_userbot&start=mock-telegram-token",
            expiresInSeconds: 900
        )
    )
    var getTelegramLinkStatusResult: Result<TelegramLinkStatusResponse, Error> = .success(
        TelegramLinkStatusResponse(linked: false, telegramId: nil, telegramIdHash: nil, usedAt: nil)
    )
    var parseVoiceWorkoutResult: Result<VoiceWorkoutParseResponse, Error>?
    var ingestInstagramReelResult: Result<IngestInstagramReelResponse, Error>?
    var ingestTextResult: Result<IngestTextResponse, Error>?
    var ingestSocialURLResult: Result<Data, Error>?
    var ingestSocialTextResult: Result<Data, Error>?
    var ingestSocialImageResult: Result<Data, Error>?
    var socialImportEquipmentContextResult: (empty: Bool, note: String?) = (true, "Mock: empty equipment")
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
    var mintTelegramLinkTokenCalled = false
    var getTelegramLinkStatusCalled = false
    var telegramLinkStatusToken: String?
    var parseVoiceWorkoutCalled = false
    var ingestInstagramReelCalled = false
    var ingestTextCalled = false
    var ingestSocialURLCalled = false
    var lastIngestSocialURL: String?
    var ingestSocialTextCalled = false
    var ingestSocialImageCalled = false
    var lastSaveWorkoutRequest: WorkoutSaveRequest?
    var saveWorkoutResult: Result<Workout, Error>?
    var transcribeAudioCalled = false
    var syncPersonalDictionaryCalled = false
    var fetchPersonalDictionaryCalled = false
    var logManualWorkoutCalled = false
    var postWorkoutCompletionCalled = false
    var postedCompletion: WorkoutCompletionRequest?
    var confirmSyncCalled = false
    var confirmedWorkoutId: String?
    var reportSyncFailedCalled = false
    /// AMA-1823: capture request_id forwarded by callers (e.g. SyncEngine)
    /// so tests can assert correlation IDs propagate to the API layer.
    var lastPostWorkoutCompletionRequestID: String?
    var lastConfirmSyncRequestID: String?
    var lastReportSyncFailedRequestID: String?
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

    func mintTelegramLinkToken() async throws -> TelegramLinkTokenResponse {
        mintTelegramLinkTokenCalled = true
        return try mintTelegramLinkTokenResult.get()
    }

    func getTelegramLinkStatus(token: String) async throws -> TelegramLinkStatusResponse {
        getTelegramLinkStatusCalled = true
        telegramLinkStatusToken = token
        return try getTelegramLinkStatusResult.get()
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

    func ingestSocialURL(url: String, platform: SocialImportPlatform) async throws -> Data {
        ingestSocialURLCalled = true
        lastIngestSocialURL = url
        guard let result = ingestSocialURLResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func ingestSocialText(text: String, source: String?) async throws -> Data {
        ingestSocialTextCalled = true
        guard let result = ingestSocialTextResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func ingestSocialImage(imageData: Data, filename: String) async throws -> Data {
        ingestSocialImageCalled = true
        guard let result = ingestSocialImageResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func socialImportEquipmentContext() async -> (empty: Bool, note: String?) {
        socialImportEquipmentContextResult
    }

    var suggestStructureResult: Result<StructureSuggestResult, Error>?
    var applyStructureResult: Result<ApplyStructureResult, Error>?
    var suggestStructureCalled = false
    var applyStructureCalled = false
    var lastSuggestStructureText: String?
    var lastApplyStructureRequest: ApplyStructureRequest?

    func suggestStructure(text: String, source: String?) async throws -> StructureSuggestResult {
        suggestStructureCalled = true
        lastSuggestStructureText = text
        guard let result = suggestStructureResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func applyStructure(_ request: ApplyStructureRequest) async throws -> ApplyStructureResult {
        applyStructureCalled = true
        lastApplyStructureRequest = request
        guard let result = applyStructureResult else {
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

    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool, requestID: String?) async throws -> WorkoutCompletionResponse {
        postWorkoutCompletionCalled = true
        postedCompletion = completion
        lastPostWorkoutCompletionRequestID = requestID
        guard let result = postWorkoutCompletionResult else {
            throw APIError.notImplemented
        }
        return try result.get()
    }

    func confirmSync(workoutId: String, deviceType: String, deviceId: String?, requestID: String?) async throws {
        confirmSyncCalled = true
        confirmedWorkoutId = workoutId
        lastConfirmSyncRequestID = requestID
        try confirmSyncResult.get()
    }

    func reportSyncFailed(workoutId: String, deviceType: String, error: String, deviceId: String?, requestID: String?) async throws {
        reportSyncFailedCalled = true
        lastReportSyncFailedRequestID = requestID
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
    var parseWorkoutTextResult: Result<ParseTextResult, Error>?
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

    func parseWorkoutText(text: String, context: String?) async throws -> ParseTextResult {
        parseWorkoutTextCalled = true
        guard let result = parseWorkoutTextResult else { throw APIError.notImplemented }
        return try result.get()
    }

    // MARK: - Agent Actions (AMA-1956)

    var fetchAgentActionsResult: Result<[AgentAction], Error> = .success([])
    var fetchAgentActionsCalled = false
    var fetchAgentActionsStatus: String?
    var respondToActionResult: Result<AgentAction, Error> = .success(.samplePending)
    var respondToActionCalled = false
    var respondToActionId: String?
    var respondToActionDecision: String?
    var undoActionResult: Result<AgentAction, Error> = .success(.sampleApplied)
    var undoActionCalled = false
    var undoActionId: String?
    var fetchCoachKnowledgeSurfaceResult: Result<CoachKnowledgeSurface, Error> = .success(.ama2229Fixture)
    var fetchCoachKnowledgeSurfaceCalled = false
    var reviewCoachKnowledgeResult: Result<CoachKnowledgeReviewResponse, Error>?
    var reviewCoachKnowledgeDelayNanoseconds: UInt64 = 0
    var reviewCoachKnowledgeCalled = false
    var reviewCoachKnowledgeCallCount = 0
    var reviewCoachKnowledgeActionId: String?
    var reviewCoachKnowledgeDecision: CoachKnowledgeReviewDecision?
    var reviewCoachKnowledgeReason: String?

    func fetchAgentActions(status: String?) async throws -> [AgentAction] {
        fetchAgentActionsCalled = true
        fetchAgentActionsStatus = status
        return try fetchAgentActionsResult.get()
    }

    func respondToAction(id: String, decision: String) async throws -> AgentAction {
        respondToActionCalled = true
        respondToActionId = id
        respondToActionDecision = decision
        return try respondToActionResult.get()
    }

    func undoAction(id: String) async throws -> AgentAction {
        undoActionCalled = true
        undoActionId = id
        return try undoActionResult.get()
    }

    func fetchCoachKnowledgeSurface() async throws -> CoachKnowledgeSurface {
        fetchCoachKnowledgeSurfaceCalled = true
        return try fetchCoachKnowledgeSurfaceResult.get()
    }

    func reviewCoachKnowledge(
        actionId: String,
        decision: CoachKnowledgeReviewDecision,
        reason: String
    ) async throws -> CoachKnowledgeReviewResponse {
        reviewCoachKnowledgeCalled = true
        reviewCoachKnowledgeCallCount += 1
        reviewCoachKnowledgeActionId = actionId
        reviewCoachKnowledgeDecision = decision
        reviewCoachKnowledgeReason = reason
        if reviewCoachKnowledgeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: reviewCoachKnowledgeDelayNanoseconds)
        }
        if let reviewCoachKnowledgeResult {
            return try reviewCoachKnowledgeResult.get()
        }
        return .ama2229Fixture(actionId: actionId, decision: decision)
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
        lastSaveWorkoutRequest = request
        if let result = saveWorkoutResult {
            return try result.get()
        }
        let source = request.source.flatMap(WorkoutSource.init(rawValue:)) ?? .manual
        return Workout(
            id: "mock-saved-\(UUID().uuidString)",
            name: request.name,
            sport: WorkoutSport(rawValue: request.sport) ?? .strength,
            duration: 1800,
            intervals: [],
            source: source,
            sourceUrl: request.sourceUrl
        )
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
    var followUserCalled = false
    var unfollowUserCalled = false

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

    func followUser(userId: String) async throws {
        followUserCalled = true
    }

    func unfollowUser(userId: String) async throws {
        unfollowUserCalled = true
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

    var fetchMyCrewsResult: Result<CrewListResponse, Error> = .success(CrewListResponse(crews: [], count: 0))
    var fetchMyCrewsCalled = false
    var fetchCrewDetailResult: Result<CrewDetail, Error> = .failure(APIError.notFound)
    var fetchCrewDetailCalled = false
    var fetchCrewFeedResult: Result<CrewFeedResponse, Error> = .success(CrewFeedResponse(posts: [], nextCursor: nil))
    var fetchCrewFeedCalled = false
    var createCrewCalled = false
    var joinCrewCalled = false
    var leaveCrewCalled = false

    func fetchMyCrews() async throws -> CrewListResponse {
        fetchMyCrewsCalled = true
        return try fetchMyCrewsResult.get()
    }

    func fetchCrewDetail(id: String) async throws -> CrewDetail {
        fetchCrewDetailCalled = true
        return try fetchCrewDetailResult.get()
    }

    func fetchCrewFeed(crewId: String) async throws -> CrewFeedResponse {
        fetchCrewFeedCalled = true
        return try fetchCrewFeedResult.get()
    }

    func createCrew(_ request: CreateCrewRequest) async throws {
        createCrewCalled = true
    }

    func joinCrew(crewId: String, request: JoinCrewRequest) async throws {
        joinCrewCalled = true
    }

    func leaveCrew(crewId: String) async throws {
        leaveCrewCalled = true
    }

    // MARK: - Leaderboards (AMA-1278)

    var fetchFriendsLeaderboardResult: Result<LeaderboardAPIResponse, Error> = .success(LeaderboardAPIResponse(dimension: "volume", period: "month", entries: []))
    var fetchFriendsLeaderboardCalled = false
    var fetchCrewLeaderboardResult: Result<LeaderboardAPIResponse, Error> = .success(LeaderboardAPIResponse(dimension: "volume", period: "month", entries: []))
    var fetchCrewLeaderboardCalled = false

    func fetchFriendsLeaderboard(dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        fetchFriendsLeaderboardCalled = true
        return try fetchFriendsLeaderboardResult.get()
    }

    func fetchCrewLeaderboard(crewId: String, dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        fetchCrewLeaderboardCalled = true
        return try fetchCrewLeaderboardResult.get()
    }

    // MARK: - Nutrition (AMA-1412)

    var analyzePhotoResult: Result<AnalyzePhotoAPIResponse, Error>?
    var analyzePhotoCalled = false
    var lookupBarcodeResult: Result<BarcodeNutritionAPIResponse, Error>?
    var lookupBarcodeCalled = false
    var parseTextResult: Result<ParseTextAPIResponse, Error>?
    var parseTextCalled = false
    var getFuelingStatusResult: Result<FuelingStatusResponse, Error>?
    var getFuelingStatusCalled = false
    var checkProteinNudgeResult: Result<ProteinNudgeResponse, Error>?
    var checkProteinNudgeCalled = false

    func analyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse {
        analyzePhotoCalled = true
        guard let result = analyzePhotoResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse {
        lookupBarcodeCalled = true
        guard let result = lookupBarcodeResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func parseText(text: String) async throws -> ParseTextAPIResponse {
        parseTextCalled = true
        guard let result = parseTextResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func getFuelingStatus() async throws -> FuelingStatusResponse {
        getFuelingStatusCalled = true
        guard let result = getFuelingStatusResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func checkProteinNudge() async throws -> ProteinNudgeResponse {
        checkProteinNudgeCalled = true
        guard let result = checkProteinNudgeResult else { throw APIError.notImplemented }
        return try result.get()
    }

    // MARK: - Devices (AMA-1996)

    var listDevicesResult: Result<[Components.Schemas.PairedDevice], Error> = .success([
        Components.Schemas.PairedDevice(
            id: "mock-garmin-955",
            lastSyncAt: "2026-05-28T14:07:00Z",
            model: "Forerunner 955",
            name: "Garmin Forerunner",
            roles: [.workouts, .recovery]
        ),
        Components.Schemas.PairedDevice(
            id: "mock-apple-watch",
            lastSyncAt: "2026-05-28T13:12:00Z",
            model: "Series 9",
            name: "Apple Watch",
            roles: [.recovery]
        )
    ])
    var pairDeviceResult: Result<Components.Schemas.PairDeviceResult, Error> = .success(
        Components.Schemas.PairDeviceResult(message: "Device paired", success: true)
    )
    var revokeDeviceResult: Result<Components.Schemas.PairDeviceResult, Error> = .success(
        Components.Schemas.PairDeviceResult(message: "Device removed", success: true)
    )
    var setDeviceRolesResult: Result<Components.Schemas.DeviceRolesResult, Error>?
    var watchDeliveryStatusResult: Result<Components.Schemas.WatchDeliveryStatus, Error> = .success(
        Components.Schemas.WatchDeliveryStatus(
            canResend: false,
            occurredAt: "2026-05-29T13:00:00Z",
            state: .pushed,
            subtitle: "Sent to Garmin Connect.",
            title: "Pushed to Garmin"
        )
    )
    var watchDeliveryStatusResults: [Result<Components.Schemas.WatchDeliveryStatus, Error>] = []
    var resendWatchDeliveryResult: Result<Components.Schemas.WatchResendResult, Error> = .success(
        Components.Schemas.WatchResendResult(deliveryIds: ["mock-delivery-1"], success: true)
    )
    var pushWatchDeliveryResult: Result<Components.Schemas.WatchResendResult, Error> = .success(
        Components.Schemas.WatchResendResult(deliveryIds: ["mock-push-1"], success: true)
    )
    var watchDeliveryStatusDelayNanoseconds: UInt64 = 0
    var resendWatchDeliveryDelayNanoseconds: UInt64 = 0
    var pushWatchDeliveryDelayNanoseconds: UInt64 = 0
    var listLibraryItemsResult: Result<Components.Schemas.LibraryItemList, Error> = .success(
        Components.Schemas.LibraryItemList(
            items: [
                Components.Schemas.LibraryItem(
                    bookmarked: false,
                    id: "mock-strength-basics",
                    kind: .workout,
                    savedAt: "2026-05-29T12:00:00Z",
                    sourceDomain: "coach.amakaflow.com",
                    sourceUrl: "https://coach.amakaflow.com/library/strength-basics",
                    tags: ["strength", "beginner"],
                    thumbnailUrl: nil,
                    title: "Strength basics for travel weeks"
                ),
                Components.Schemas.LibraryItem(
                    bookmarked: false,
                    id: "mock-mobility-video",
                    kind: .video,
                    savedAt: "2026-05-29T12:05:00Z",
                    sourceDomain: "youtube.com",
                    sourceUrl: "https://youtube.com/watch?v=mock",
                    tags: ["mobility"],
                    thumbnailUrl: nil,
                    title: "10-minute ankle mobility reset"
                ),
                Components.Schemas.LibraryItem(
                    bookmarked: false,
                    id: "mock-zone-two",
                    kind: .article,
                    savedAt: "2026-05-29T12:10:00Z",
                    sourceDomain: "trainingpeaks.com",
                    sourceUrl: "https://trainingpeaks.com/mock-zone-two",
                    tags: ["endurance", "base"],
                    thumbnailUrl: nil,
                    title: "Why zone two still matters"
                ),
                Components.Schemas.LibraryItem(
                    bookmarked: false,
                    id: "mock-hyrox-plan",
                    kind: .plan,
                    savedAt: "2026-05-29T12:15:00Z",
                    sourceDomain: "amakaflow.com",
                    sourceUrl: "https://amakaflow.com/plans/hyrox-mock",
                    tags: ["hyrox", "strength"],
                    thumbnailUrl: nil,
                    title: "Four-week HYROX tune-up"
                )
            ],
            total: 4
        )
    )
    var getLibraryItemResult: Result<Components.Schemas.LibraryItemDetail, Error> = .success(
        Components.Schemas.LibraryItemDetail(
            bookmarked: false,
            id: "mock-strength-basics",
            keyTakeaways: ["Use RPE when equipment changes.", "Keep strength blocks compact."],
            kind: .workout,
            microSummary: "Travel-friendly strength",
            savedAt: "2026-05-29T12:00:00Z",
            sourceDomain: "coach.amakaflow.com",
            sourceUrl: "https://coach.amakaflow.com/library/strength-basics",
            summary: "A compact strength template for weeks when travel or equipment limits your normal gym routine.",
            tags: ["strength", "beginner"],
            thumbnailUrl: nil,
            title: "Strength basics for travel weeks"
        )
    )
    var listMessagingChannelsResult: Result<Components.Schemas.MessagingChannelList, Error> = .success(
        Components.Schemas.MessagingChannelList(
            channels: [
                Components.Schemas.MessagingChannel(
                    comingSoon: false,
                    connected: true,
                    handle: "@mock_amaka",
                    id: "telegram",
                    name: "Telegram",
                    prefs: Components.Schemas.ChannelPrefs(briefing: true, checkin: true, quietEnd: "07:00", quietStart: "21:00", swap: false)
                ),
                Components.Schemas.MessagingChannel(
                    comingSoon: true,
                    connected: false,
                    handle: nil,
                    id: "whatsapp",
                    name: "WhatsApp",
                    prefs: Components.Schemas.ChannelPrefs(briefing: false, checkin: false, swap: false)
                )
            ],
            deliveryLive: false
        )
    )
    var setChannelPrefsResult: Result<Components.Schemas.ChannelPrefsResult, Error>?
    var setChannelPrefsResultsByChannel: [String: Result<Components.Schemas.ChannelPrefsResult, Error>] = [:]
    var setChannelPrefsDelayNanoseconds: UInt64 = 0
    var setChannelPrefsDelaysByChannel: [String: UInt64] = [:]
    var listDevicesCalled = false
    var listLibraryItemsCalled = false
    var getLibraryItemCalled = false
    var pairDeviceCalled = false
    var revokeDeviceCalled = false
    var setDeviceRolesCalled = false
    var watchDeliveryStatusCalled = false
    var watchDeliveryStatusCallCount = 0
    var resendWatchDeliveryCalled = false
    var resendWatchDeliveryCallCount = 0
    var pushWatchDeliveryCalled = false
    var pushWatchDeliveryCallCount = 0
    var lastPushWatchDeliveryWorkoutId: String?
    var listMessagingChannelsCalled = false
    var setChannelPrefsCalled = false
    var setChannelPrefsCallCount = 0
    var lastPairedShortCode: String?
    var lastRevokedDeviceId: String?
    var lastSetDeviceRolesId: String?
    var lastSetDeviceRoles: [Components.Schemas.DeviceRole]?
    var lastWatchDeliveryWorkoutId: String?
    var lastResendWatchDeliveryWorkoutId: String?
    var lastListLibraryItemsKind: Components.Schemas.LibraryKind?
    var lastListLibraryItemsTag: String?
    var lastGetLibraryItemId: String?
    var lastSetChannelPrefsId: String?
    var lastSetChannelPrefs: Components.Schemas.ChannelPrefsRequest?

    func listDevices() async throws -> [Components.Schemas.PairedDevice] {
        listDevicesCalled = true
        return try listDevicesResult.get()
    }

    func pairDevice(shortCode: String) async throws -> Components.Schemas.PairDeviceResult {
        pairDeviceCalled = true
        lastPairedShortCode = shortCode
        return try pairDeviceResult.get()
    }

    func revokeDevice(id: String) async throws -> Components.Schemas.PairDeviceResult {
        revokeDeviceCalled = true
        lastRevokedDeviceId = id
        return try revokeDeviceResult.get()
    }

    func setDeviceRoles(
        id: String,
        roles: [Components.Schemas.DeviceRole]
    ) async throws -> Components.Schemas.DeviceRolesResult {
        setDeviceRolesCalled = true
        lastSetDeviceRolesId = id
        lastSetDeviceRoles = roles
        if let setDeviceRolesResult {
            return try setDeviceRolesResult.get()
        }
        return Components.Schemas.DeviceRolesResult(roles: roles, success: true)
    }

    func watchDeliveryStatus(workoutId: String) async throws -> Components.Schemas.WatchDeliveryStatus {
        watchDeliveryStatusCalled = true
        watchDeliveryStatusCallCount += 1
        lastWatchDeliveryWorkoutId = workoutId
        if watchDeliveryStatusDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: watchDeliveryStatusDelayNanoseconds)
        }
        if !watchDeliveryStatusResults.isEmpty {
            return try watchDeliveryStatusResults.removeFirst().get()
        }
        return try watchDeliveryStatusResult.get()
    }

    func resendWatchDelivery(workoutId: String) async throws -> Components.Schemas.WatchResendResult {
        resendWatchDeliveryCalled = true
        resendWatchDeliveryCallCount += 1
        lastResendWatchDeliveryWorkoutId = workoutId
        if resendWatchDeliveryDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: resendWatchDeliveryDelayNanoseconds)
        }
        return try resendWatchDeliveryResult.get()
    }

    func pushWatchDelivery(workoutId: String) async throws -> Components.Schemas.WatchResendResult {
        pushWatchDeliveryCalled = true
        pushWatchDeliveryCallCount += 1
        lastPushWatchDeliveryWorkoutId = workoutId
        if pushWatchDeliveryDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: pushWatchDeliveryDelayNanoseconds)
        }
        return try pushWatchDeliveryResult.get()
    }

    func listLibraryItems(
        kind: Components.Schemas.LibraryKind?,
        tag: String?
    ) async throws -> Components.Schemas.LibraryItemList {
        listLibraryItemsCalled = true
        lastListLibraryItemsKind = kind
        lastListLibraryItemsTag = tag
        return try listLibraryItemsResult.get()
    }

    func getLibraryItem(id: String) async throws -> Components.Schemas.LibraryItemDetail {
        getLibraryItemCalled = true
        lastGetLibraryItemId = id
        return try getLibraryItemResult.get()
    }

    var deleteKnowledgeCardResult: Result<Void, Error> = .success(())
    var deleteWorkoutResult: Result<Void, Error> = .success(())
    var deleteKnowledgeCardCalled = false
    var deleteWorkoutCalled = false
    var lastDeletedKnowledgeCardID: String?
    var lastDeletedWorkoutID: String?

    func deleteKnowledgeCard(id: String) async throws {
        deleteKnowledgeCardCalled = true
        lastDeletedKnowledgeCardID = id
        try deleteKnowledgeCardResult.get()
    }

    func deleteWorkout(id: String) async throws {
        deleteWorkoutCalled = true
        lastDeletedWorkoutID = id
        try deleteWorkoutResult.get()
    }

    func listMessagingChannels() async throws -> Components.Schemas.MessagingChannelList {
        listMessagingChannelsCalled = true
        return try listMessagingChannelsResult.get()
    }

    func setChannelPrefs(
        channelId: String,
        prefs: Components.Schemas.ChannelPrefsRequest
    ) async throws -> Components.Schemas.ChannelPrefsResult {
        setChannelPrefsCalled = true
        setChannelPrefsCallCount += 1
        lastSetChannelPrefsId = channelId
        lastSetChannelPrefs = prefs
        let delay = setChannelPrefsDelaysByChannel[channelId] ?? setChannelPrefsDelayNanoseconds
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        if let channelResult = setChannelPrefsResultsByChannel[channelId] {
            return try channelResult.get()
        }
        if let setChannelPrefsResult {
            return try setChannelPrefsResult.get()
        }
        return Components.Schemas.ChannelPrefsResult(
            channelId: channelId,
            prefs: Components.Schemas.ChannelPrefs(
                briefing: prefs.briefing,
                checkin: prefs.checkin,
                quietEnd: prefs.quietEnd,
                quietStart: prefs.quietStart,
                swap: prefs.swap
            ),
            success: true
        )
    }

    // MARK: - Coaching Profile (AMA-1995)

    var getCoachingProfileResult: Result<Components.Schemas.CoachingProfile?, Error> = .success(
        Components.Schemas.CoachingProfile(
            createdAt: "2026-05-28T00:00:00Z",
            equipment: nil,
            experienceLevel: "intermediate",
            goals: nil,
            primaryGoal: "general_fitness",
            sessionsPerWeek: 3,
            updatedAt: "2026-05-28T00:00:00Z",
            userId: "mock-user"
        )
    )
    var upsertCoachingProfileResult: Result<Components.Schemas.CoachingProfile, Error>?
    var postReadinessSampleResult: Result<ReadinessSampleWriteResult, Error>?
    var readinessTodayResult: Result<Components.Schemas.ReadinessToday, Error> = .success(
        Components.Schemas.ReadinessToday(
            date: "2026-05-30",
            hasData: true,
            hrv: 62.4,
            restingHr: 48,
            sleepHours: 7.6,
            sleepQuality: "good",
            source: "apple_health"
        )
    )
    var readinessTrendResult: Result<Components.Schemas.ReadinessTrend, Error> = .success(
        Components.Schemas.ReadinessTrend(
            days: 7,
            metric: "hrv",
            points: [
                Components.Schemas.ReadinessTrendPoint(date: "2026-05-24", value: 57.0),
                Components.Schemas.ReadinessTrendPoint(date: "2026-05-25", value: nil),
                Components.Schemas.ReadinessTrendPoint(date: "2026-05-26", value: 59.5),
                Components.Schemas.ReadinessTrendPoint(date: "2026-05-27", value: 61.0),
                Components.Schemas.ReadinessTrendPoint(date: "2026-05-28", value: nil),
                Components.Schemas.ReadinessTrendPoint(date: "2026-05-29", value: 60.2),
                Components.Schemas.ReadinessTrendPoint(date: "2026-05-30", value: 62.4)
            ]
        )
    )
    var readinessSourcePrefsResult: Result<Components.Schemas.ReadinessSourcePrefs, Error>?
    var setReadinessSourcePrefResult: Result<Components.Schemas.ReadinessSourcePref, Error>?
    var setReadinessSourcePrefDelayNanoseconds: UInt64 = 0
    var fixtureSourcePrefs: [Components.Schemas.ReadinessSourcePref] = [
        Components.Schemas.ReadinessSourcePref(metric: "hrv", source: "apple_health"),
        Components.Schemas.ReadinessSourcePref(metric: "sleep", source: "apple_health"),
        Components.Schemas.ReadinessSourcePref(metric: "rhr", source: "garmin")
    ]
    var getCoachingProfileCalled = false
    var upsertCoachingProfileCalled = false
    var postReadinessSampleCalled = false
    var postReadinessSampleCallCount = 0
    var readinessTodayCalled = false
    var readinessTrendCalled = false
    var readinessSourcePrefsCalled = false
    var setReadinessSourcePrefCalled = false
    var setReadinessSourcePrefCallCount = 0
    var lastCoachingProfileUpsert: Components.Schemas.CoachingProfileUpsert?
    var lastReadinessSample: (hrv: Double?, restingHr: Int?, sleepHours: Double?, sleepQuality: String?, sampleDate: String?)?
    var lastReadinessTrendRequest: (metric: String, days: Int)?
    var lastReadinessSourcePrefRequest: (metric: String, source: String, deviceId: String?)?

    func getCoachingProfile() async throws -> Components.Schemas.CoachingProfile? {
        getCoachingProfileCalled = true
        return try getCoachingProfileResult.get()
    }

    func upsertCoachingProfile(_ profile: Components.Schemas.CoachingProfileUpsert) async throws -> Components.Schemas.CoachingProfile {
        upsertCoachingProfileCalled = true
        lastCoachingProfileUpsert = profile
        if let upsertCoachingProfileResult {
            return try upsertCoachingProfileResult.get()
        }
        return Components.Schemas.CoachingProfile(
            createdAt: "2026-05-28T00:00:00Z",
            equipment: profile.equipment,
            experienceLevel: profile.experienceLevel,
            goals: profile.goals,
            injuriesLimitations: profile.injuriesLimitations,
            preferredDays: profile.preferredDays,
            primaryGoal: profile.primaryGoal,
            sessionDurationMinutes: profile.sessionDurationMinutes,
            sessionsPerWeek: profile.sessionsPerWeek,
            updatedAt: "2026-05-28T00:00:01Z",
            userId: "mock-user"
        )
    }

    func postReadinessSample(
        hrv: Double?,
        restingHr: Int?,
        sleepHours: Double?,
        sleepQuality: String?,
        sampleDate: String?
    ) async throws -> ReadinessSampleWriteResult {
        postReadinessSampleCalled = true
        postReadinessSampleCallCount += 1
        lastReadinessSample = (hrv, restingHr, sleepHours, sleepQuality, sampleDate)
        if hrv == nil, restingHr == nil, sleepHours == nil, sleepQuality == nil {
            throw APIError.serverErrorWithBody(422, "{\"detail\":\"At least one metric is required.\"}")
        }
        if let postReadinessSampleResult {
            return try postReadinessSampleResult.get()
        }
        return ReadinessSampleWriteResult(
            success: true,
            date: sampleDate ?? "2026-05-30",
            source: "apple_health"
        )
    }

    func readinessToday() async throws -> Components.Schemas.ReadinessToday {
        readinessTodayCalled = true
        return try readinessTodayResult.get()
    }

    func readinessTrend(metric: String, days: Int) async throws -> Components.Schemas.ReadinessTrend {
        readinessTrendCalled = true
        lastReadinessTrendRequest = (metric, days)
        return try readinessTrendResult.get()
    }

    func readinessSourcePrefs() async throws -> Components.Schemas.ReadinessSourcePrefs {
        readinessSourcePrefsCalled = true
        if let readinessSourcePrefsResult {
            return try readinessSourcePrefsResult.get()
        }
        return Components.Schemas.ReadinessSourcePrefs(prefs: fixtureSourcePrefs)
    }

    func setReadinessSourcePref(metric: String, source: String, deviceId: String?) async throws -> Components.Schemas.ReadinessSourcePref {
        setReadinessSourcePrefCalled = true
        setReadinessSourcePrefCallCount += 1
        lastReadinessSourcePrefRequest = (metric, source, deviceId)
        if setReadinessSourcePrefDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: setReadinessSourcePrefDelayNanoseconds)
        }
        if let setReadinessSourcePrefResult {
            return try setReadinessSourcePrefResult.get()
        }
        let updated = Components.Schemas.ReadinessSourcePref(deviceId: deviceId, metric: metric, source: source)
        if let index = fixtureSourcePrefs.firstIndex(where: { $0.metric == metric }) {
            fixtureSourcePrefs[index] = updated
        } else {
            fixtureSourcePrefs.append(updated)
        }
        return updated
    }

    // MARK: - Coach Suggestions (AMA-1412)

    var suggestWorkoutResult: Result<SuggestWorkoutResponse, Error>?
    var suggestWorkoutCalled = false
    var suggestWorkoutCallCount = 0
    var lastSuggestWorkoutRequest: SuggestWorkoutRequest?
    var postRPEFeedbackResult: Result<RPEFeedbackResponse, Error>?
    var postRPEFeedbackCalled = false

    func suggestWorkout(request: SuggestWorkoutRequest) async throws -> SuggestWorkoutResponse {
        suggestWorkoutCalled = true
        suggestWorkoutCallCount += 1
        lastSuggestWorkoutRequest = request
        guard let result = suggestWorkoutResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse {
        postRPEFeedbackCalled = true
        guard let result = postRPEFeedbackResult else { throw APIError.notImplemented }
        return try result.get()
    }

    // MARK: - Program Generation (AMA-1413)

    var generateProgramResult: Result<ProgramGenerationResponse, Error>?
    var generateProgramCalled = false
    var lastGenerateProgramRequest: ProgramGenerationRequest?
    var fetchGenerationStatusResult: Result<ProgramGenerationStatus, Error>?
    var fetchGenerationStatusCalled = false
    var updateProgramStatusCalled = false
    var lastUpdateProgramStatusId: String?
    var lastUpdateProgramStatus: String?
    var updateProgramProgressCalled = false
    var lastUpdateProgramProgressId: String?
    var lastUpdateProgramProgressWeek: Int?
    var deleteProgramCalled = false
    var lastDeleteProgramId: String?
    var completeWorkoutCalled = false
    var lastCompleteWorkoutId: String?

    func generateProgram(request: ProgramGenerationRequest) async throws -> ProgramGenerationResponse {
        generateProgramCalled = true
        lastGenerateProgramRequest = request
        guard let result = generateProgramResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func fetchGenerationStatus(jobId: String) async throws -> ProgramGenerationStatus {
        fetchGenerationStatusCalled = true
        guard let result = fetchGenerationStatusResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func updateProgramStatus(id: String, status: String) async throws {
        updateProgramStatusCalled = true
        lastUpdateProgramStatusId = id
        lastUpdateProgramStatus = status
    }

    func updateProgramProgress(id: String, currentWeek: Int) async throws {
        updateProgramProgressCalled = true
        lastUpdateProgramProgressId = id
        lastUpdateProgramProgressWeek = currentWeek
    }

    func deleteProgram(id: String) async throws {
        deleteProgramCalled = true
        lastDeleteProgramId = id
    }

    func completeWorkout(workoutId: String) async throws {
        completeWorkoutCalled = true
        lastCompleteWorkoutId = workoutId
    }

    // MARK: - Volume Analytics (AMA-1414)

    var fetchVolumeAnalyticsResult: Result<VolumeAnalyticsResponse, Error>?
    var fetchVolumeAnalyticsCalled = false
    var lastFetchVolumeStartDate: String?
    var lastFetchVolumeEndDate: String?
    var lastFetchVolumeGranularity: String?

    func fetchVolumeAnalytics(startDate: String, endDate: String, granularity: String) async throws -> VolumeAnalyticsResponse {
        fetchVolumeAnalyticsCalled = true
        lastFetchVolumeStartDate = startDate
        lastFetchVolumeEndDate = endDate
        lastFetchVolumeGranularity = granularity
        guard let result = fetchVolumeAnalyticsResult else { throw APIError.notImplemented }
        return try result.get()
    }

    // MARK: - Bulk Import (AMA-1415)

    var detectImportResult: Result<BulkDetectResponse, Error>?
    var detectImportCalled = false
    var lastDetectRequest: BulkDetectRequest?

    var matchExercisesResult: Result<BulkMatchResponse, Error>?
    var matchExercisesCalled = false
    var lastMatchRequest: BulkMatchRequest?

    var previewImportResult: Result<BulkPreviewResponse, Error>?
    var previewImportCalled = false
    var lastPreviewRequest: BulkPreviewRequest?

    var executeImportResult: Result<BulkExecuteResponse, Error>?
    var executeImportCalled = false
    var lastExecuteRequest: BulkExecuteRequest?

    var fetchImportStatusResult: Result<BulkImportStatus, Error>?
    var fetchImportStatusCalled = false
    var lastFetchImportStatusJobId: String?

    var cancelImportCalled = false
    var lastCancelImportJobId: String?

    func detectImport(request: BulkDetectRequest) async throws -> BulkDetectResponse {
        detectImportCalled = true
        lastDetectRequest = request
        guard let result = detectImportResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func matchExercises(request: BulkMatchRequest) async throws -> BulkMatchResponse {
        matchExercisesCalled = true
        lastMatchRequest = request
        guard let result = matchExercisesResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func previewImport(request: BulkPreviewRequest) async throws -> BulkPreviewResponse {
        previewImportCalled = true
        lastPreviewRequest = request
        guard let result = previewImportResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func executeImport(request: BulkExecuteRequest) async throws -> BulkExecuteResponse {
        executeImportCalled = true
        lastExecuteRequest = request
        guard let result = executeImportResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func fetchImportStatus(jobId: String, profileId: String) async throws -> BulkImportStatus {
        fetchImportStatusCalled = true
        lastFetchImportStatusJobId = jobId
        guard let result = fetchImportStatusResult else { throw APIError.notImplemented }
        return try result.get()
    }

    func cancelImport(jobId: String, profileId: String) async throws {
        cancelImportCalled = true
        lastCancelImportJobId = jobId
    }

    // MARK: - Privacy (AMA-315)

    var exportUserDataResult: Result<Data, Error> = .success(Data("{}".utf8))
    var exportUserDataCalled = false

    var deleteAccountResult: Result<Void, Error> = .success(())
    var deleteAccountCalled = false

    func exportUserData() async throws -> Data {
        exportUserDataCalled = true
        return try exportUserDataResult.get()
    }

    func deleteAccount() async throws {
        deleteAccountCalled = true
        try deleteAccountResult.get()
    }
}


extension CoachKnowledgeSurface {
    static var ama2229Fixture: CoachKnowledgeSurface {
        CoachKnowledgeSurface(
            mode: "mock",
            readableOrder: ["sections", "provenance"],
            sections: [
                CoachKnowledgeSection(
                    id: "goals",
                    title: "Goals",
                    summary: "",
                    facts: [
                        CoachKnowledgeFact(
                            id: "fact-goal",
                            text: "HYROX race - May 2026",
                            state: "accepted",
                            category: "goal",
                            confidence: 0.9,
                            sensitivity: "public_or_low",
                            source: CoachKnowledgeSourceRef(
                                kind: "user",
                                sourceId: "source-goal",
                                label: "You told me",
                                title: "Goal chat",
                                uri: "",
                                quote: "HYROX in May.",
                                confidence: 0.9,
                                occurredAt: "2026-04-20"
                            ),
                            provenance: [
                                CoachKnowledgeSourceRef(
                                    kind: "user",
                                    sourceId: "source-goal",
                                    label: "You told me",
                                    title: "Goal chat",
                                    uri: "",
                                    quote: "HYROX in May.",
                                    confidence: 0.9,
                                    occurredAt: "2026-04-20"
                                )
                            ]
                        )
                    ]
                )
            ],
            sensitivePending: [
                CoachKnowledgePendingSensitiveFact(
                    id: "fact-knee-review",
                    actionId: "pa-knee-review",
                    text: "Possible left knee issue",
                    category: "Injury",
                    state: "needs_review",
                    reviewState: "pending_user",
                    heldLabel: "HELD · NOT APPLIED",
                    prompt: "Treat this as an active injury to plan around?",
                    source: CoachKnowledgeSourceRef(
                        kind: "chat",
                        sourceId: "source-knee-chat",
                        label: "From chat",
                        title: "Telegram",
                        uri: "",
                        quote: "Knee was sore.",
                        confidence: 0.7,
                        occurredAt: "2026-04-22"
                    ),
                    provenance: [],
                    detail: "Not accepted coach truth."
                )
            ],
            contradictions: [
                CoachKnowledgeContradiction(
                    id: "contradiction-knee",
                    state: "needs_user_review",
                    claimIdA: "knee-fine",
                    claimIdB: "fact-knee-review",
                    options: [
                        CoachKnowledgeContradictionOption(
                            text: "Knee feels fine now",
                            source: CoachKnowledgeSourceRef(
                                kind: "chat",
                                sourceId: "source-knee-fine",
                                label: "From chat",
                                title: "Telegram",
                                uri: "",
                                quote: "Knee feels fine now.",
                                confidence: 0.8,
                                occurredAt: "2026-04-25"
                            )
                        ),
                        CoachKnowledgeContradictionOption(
                            text: "Logged knee pain twice this week",
                            source: CoachKnowledgeSourceRef(
                                kind: "device",
                                sourceId: "source-knee-device",
                                label: "From device",
                                title: "Device note",
                                uri: "",
                                quote: "Knee pain logged twice.",
                                confidence: 0.7,
                                occurredAt: "2026-04-24"
                            )
                        )
                    ]
                )
            ],
            dataGaps: [
                CoachKnowledgeGap(
                    id: "gap-hrv",
                    title: "No HRV for 3 days",
                    detail: "Connect a source or log manually.",
                    mode: "data_gap",
                    actionLabel: "Connect a source"
                )
            ],
            contract: CoachKnowledgeContract(
                readRoute: "GET /coach/wiki/surface",
                reviewQueueRoute: "GET /coach/wiki/review-queue",
                reviewActionRoutes: [
                    "POST /coach/wiki/review-actions/{action_id}/approve",
                    "POST /coach/wiki/review-actions/{action_id}/reject"
                ],
                factStates: ["accepted", "rejected", "superseded", "contradicted", "needs_review"],
                mode: "mock"
            )
        )
    }
}

extension CoachKnowledgeReviewResponse {
    static var ama2229ApprovedFixture: CoachKnowledgeReviewResponse {
        ama2229Fixture(actionId: "pa-knee-review", decision: .approve)
    }

    static var ama2229RejectedFixture: CoachKnowledgeReviewResponse {
        ama2229Fixture(actionId: "pa-knee-review", decision: .reject)
    }

    static func ama2229Fixture(
        actionId: String,
        decision: CoachKnowledgeReviewDecision
    ) -> CoachKnowledgeReviewResponse {
        CoachKnowledgeReviewResponse(
            operation: decision.rawValue,
            claim: ["id": .string("fact-knee-review")],
            pendingAction: [
                "id": .string(actionId),
                "status": .string(decision == .approve ? "approved" : "rejected")
            ],
            audit: ["boundary": .string("coach_wiki_review")],
            cacheInvalidated: true
        )
    }
}