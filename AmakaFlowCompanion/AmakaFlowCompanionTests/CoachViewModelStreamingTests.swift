//
//  CoachViewModelStreamingTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for CoachViewModel SSE streaming behavior (AMA-1410)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class CoachViewModelStreamingTests: XCTestCase {

    var viewModel: CoachViewModel!
    var mockStreamService: MockChatStreamService!
    var mockSessionClient: MockCoachSessionClient!
    var mockPairingService: MockPairingService!

    override func setUp() async throws {
        mockStreamService = MockChatStreamService()
        mockSessionClient = MockCoachSessionClient()
        mockPairingService = MockPairingService()
        mockPairingService.storedToken = "test-jwt-token"
        mockPairingService.isPaired = true

        let dependencies = AppDependencies(
            apiService: MockAPIService(),
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: mockStreamService,
            coachSessionClient: mockSessionClient
        )

        viewModel = CoachViewModel(dependencies: dependencies)
    }

    func testSendMessageAddsUserMessage() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Hello!"),
            .messageEnd(sessionId: "s1", tokensUsed: 10, latencyMs: 100)
        ]

        await viewModel.sendMessage("Hi coach")

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].content, "Hi coach")
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertEqual(viewModel.messages[1].content, "Hello!")
    }

    func testStreamingAppendsContentDeltas() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Hello "),
            .contentDelta(text: "world!"),
            .messageEnd(sessionId: "s1", tokensUsed: 20, latencyMs: 200)
        ]

        await viewModel.sendMessage("Test")

        XCTAssertEqual(viewModel.messages[1].content, "Hello world!")
    }

    func testSessionIdPersisted() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "session-abc", traceId: nil),
            .messageEnd(sessionId: "session-abc", tokensUsed: 5, latencyMs: 50)
        ]

        await viewModel.sendMessage("Test")

        XCTAssertEqual(viewModel.sessionId, "session-abc")
    }

    func testToolCallTracked() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .functionCall(id: "t1", name: "search_workout_library"),
            .functionResult(toolUseId: "t1", name: "search_workout_library", result: "{}"),
            .contentDelta(text: "Found it!"),
            .messageEnd(sessionId: "s1", tokensUsed: 100, latencyMs: 1000)
        ]

        await viewModel.sendMessage("Find me a workout")

        let assistantMsg = viewModel.messages[1]
        XCTAssertEqual(assistantMsg.toolCalls.count, 1)
        XCTAssertEqual(assistantMsg.toolCalls[0].name, "search_workout_library")
        XCTAssertEqual(assistantMsg.toolCalls[0].status, .completed)
    }

    func testStageProgression() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .stage(stage: .analyzing, message: "Analyzing"),
            .stage(stage: .searching, message: "Searching"),
            .stage(stage: .complete, message: "Done"),
            .contentDelta(text: "Result"),
            .messageEnd(sessionId: "s1", tokensUsed: 50, latencyMs: 500)
        ]

        await viewModel.sendMessage("Plan my week")

        XCTAssertTrue(viewModel.completedStages.contains(.analyzing))
        XCTAssertTrue(viewModel.completedStages.contains(.searching))
    }

    func testErrorEventSetsErrorAndRateLimit() async {
        // AMA-1803 P2: SSE `.error` events now route through CTAError
        // (.lyingSuccess) so the View can render Retry/Report and
        // surface the server's `type` as error_code. Rate-limit gets
        // its dedicated banner via rateLimitInfo, separately.
        mockStreamService.eventsToYield = [
            .error(type: "rate_limit_exceeded", message: "Too many requests", usage: 50, limit: 50)
        ]

        await viewModel.sendMessage("Test")

        XCTAssertNotNil(viewModel.error)
        XCTAssertEqual(viewModel.rateLimitInfo?.usage, 50)
        if case .lyingSuccess(let message, let errorCode, _) = viewModel.error {
            XCTAssertEqual(message, "Too many requests")
            XCTAssertEqual(errorCode, "rate_limit_exceeded")
        } else {
            XCTFail("expected .lyingSuccess on SSE .error event, got \(String(describing: viewModel.error))")
        }
        XCTAssertFalse(viewModel.error?.isRetryable ?? true,
                       "rate-limit SSE errors should remain deterministic and non-retryable")
    }

    // MARK: - AMA-1803 P2: typed CTAError tests

    func testSSEErrorWithoutRateLimitSurfacesAsLyingSuccessCTAError() async {
        // Non-rate-limit error event still classifies as
        // lyingSuccess with the server's type as error_code.
        mockStreamService.eventsToYield = [
            .error(type: "coach_unavailable", message: "Coach is offline", usage: nil, limit: nil)
        ]

        await viewModel.sendMessage("Hi")

        guard case .lyingSuccess(let msg, let code, _) = viewModel.error else {
            return XCTFail("expected .lyingSuccess, got \(String(describing: viewModel.error))")
        }
        XCTAssertEqual(msg, "Coach is offline")
        XCTAssertEqual(code, "coach_unavailable")
        XCTAssertNil(viewModel.rateLimitInfo, "non-rate-limit must not populate rateLimitInfo")
        XCTAssertTrue(viewModel.error?.isRetryable ?? false,
                      "dependency-down SSE errors should offer retry")
    }

    func testRetryLastMessageReSendsAndClearsError() async {
        // First call fails with a server-reported error.
        mockStreamService.eventsToYield = [
            .error(type: "transient", message: "Try again", usage: nil, limit: nil)
        ]
        await viewModel.sendMessage("Hello coach")
        XCTAssertNotNil(viewModel.error)

        // Retry: queue a clean response. retryLastMessage re-sends the
        // last user message and clears the error if the new run succeeds.
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Hi back"),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]
        await viewModel.retryLastMessage()

        XCTAssertNil(viewModel.error, "successful retry must clear the typed error")
    }

    func testTransportFailureSetsRetryableCTAErrorAndRetryLastMessageReSends() async {
        mockStreamService.errorToThrow = URLError(.notConnectedToInternet)

        await viewModel.sendMessage("Hello over a bad connection")

        guard case .network(let code, _) = viewModel.error else {
            return XCTFail("expected .network CTAError, got \(String(describing: viewModel.error))")
        }
        XCTAssertEqual(code, .notConnectedToInternet)
        XCTAssertTrue(viewModel.error?.isRetryable ?? false, "offline transport failures must offer Retry")
        XCTAssertTrue(viewModel.messages.isEmpty, "failed empty stream should remove the optimistic user/assistant pair")

        mockStreamService.errorToThrow = nil
        mockStreamService.streamCalled = false
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Back online"),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]

        await viewModel.retryLastMessage()

        XCTAssertTrue(mockStreamService.streamCalled, "retryLastMessage must re-send through the SSE harness")
        XCTAssertNil(viewModel.error, "successful retry must clear the typed network error")
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.content, "Hello over a bad connection")
        XCTAssertEqual(viewModel.messages.last?.content, "Back online")
    }

    func testAcknowledgeErrorClearsTypedError() async {
        mockStreamService.eventsToYield = [
            .error(type: "x", message: "y", usage: nil, limit: nil)
        ]
        await viewModel.sendMessage("Trigger")
        XCTAssertNotNil(viewModel.error)

        viewModel.acknowledgeError()

        XCTAssertNil(viewModel.error, "acknowledgeError must drop the banner")
    }

    func testStartNewChatClearsTypedErrorToo() async {
        mockStreamService.eventsToYield = [
            .error(type: "x", message: "y", usage: nil, limit: nil)
        ]
        await viewModel.sendMessage("Trigger")
        XCTAssertNotNil(viewModel.error)

        viewModel.startNewChat()

        XCTAssertNil(viewModel.error)
        XCTAssertNil(viewModel.rateLimitInfo)
    }

    func testNewChatClearsState() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Hello"),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]

        await viewModel.sendMessage("Hi")
        XCTAssertEqual(viewModel.messages.count, 2)

        viewModel.startNewChat()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.sessionId)
    }

    func testStreamServiceCalledWithToken() async {
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]

        await viewModel.sendMessage("Hi")

        XCTAssertTrue(mockStreamService.streamCalled)
    }

    func testLoadMessagesPopulatesHistoryWhenSessionIdPresent() async {
        viewModel.sessionId = "sess-restore"
        mockSessionClient.messagesToReturn = [
            RestoredSessionMessage(
                role: .user,
                content: "Remember this test message for restore",
                timestamp: Date(timeIntervalSince1970: 1_718_000_000)
            ),
            RestoredSessionMessage(
                role: .assistant,
                content: "Got it — I'll remember that.",
                timestamp: Date(timeIntervalSince1970: 1_718_000_030)
            )
        ]

        await viewModel.loadMessagesIfNeeded()

        XCTAssertTrue(mockSessionClient.fetchCalled)
        XCTAssertEqual(mockSessionClient.lastSessionId, "sess-restore")
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].content, "Remember this test message for restore")
        XCTAssertTrue(viewModel.didRestoreConversation)
    }

    func testLoadMessagesClearsStaleSessionOn404() async {
        viewModel.sessionId = "stale-session"
        mockSessionClient.errorToThrow = CoachSessionError.sessionNotFound

        await viewModel.loadMessagesIfNeeded()

        XCTAssertNil(viewModel.sessionId)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testLoadMessagesSkipsWhenMessagesAlreadyPresent() async {
        viewModel.sessionId = "sess-restore"
        viewModel.messages = [ChatMessage(role: .user, content: "Already here")]

        await viewModel.loadMessagesIfNeeded()

        XCTAssertFalse(mockSessionClient.fetchCalled)
    }

    // MARK: - Issue 307: auth token error as CTAError, not chat bubble

    func testMissingTokenSetsUnauthenticatedCTAErrorNotChatBubble() async {
        mockPairingService.storedToken = nil

        await viewModel.sendMessage("Hello coach")

        guard case .unauthenticated = viewModel.error else {
            return XCTFail("expected .unauthenticated CTAError when token is missing, got \(String(describing: viewModel.error))")
        }
        XCTAssertTrue(viewModel.messages.isEmpty, "auth failure must not leave chat bubbles")
        XCTAssertFalse(viewModel.isStreaming, "streaming must be reset after auth failure")
    }

    // MARK: - Issue 307: session ID re-keyed on auth resolve

    func testSessionIdRekeyedToRealUserWhenAuthResolvesWithActiveSession() async {
        let userId = "user_rekey_307"
        let realKey = "coach_chat_session_id_\(userId)"
        let unknownKey = "coach_chat_session_id_unknown"
        defer {
            UserDefaults.standard.removeObject(forKey: realKey)
            UserDefaults.standard.removeObject(forKey: unknownKey)
        }

        let pairingService = MockPairingService()
        pairingService.storedToken = "test-token"
        pairingService.isPaired = true
        pairingService.userProfile = nil

        let streamService = MockChatStreamService()
        streamService.eventsToYield = [
            .messageStart(sessionId: "sess-rekey-307", traceId: nil),
            .contentDelta(text: "Hello!"),
            .messageEnd(sessionId: "sess-rekey-307", tokensUsed: 5, latencyMs: 50)
        ]

        let dependencies = AppDependencies(
            apiService: MockAPIService(),
            pairingService: pairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: streamService,
            coachSessionClient: MockCoachSessionClient()
        )

        let vm = CoachViewModel(dependencies: dependencies)

        // Send message before auth resolves — session ID lands in "unknown" key
        await vm.sendMessage("Hi")
        XCTAssertEqual(vm.sessionId, "sess-rekey-307")

        // Auth resolves with real user ID while messages exist
        pairingService.userProfile = UserProfile(
            id: userId,
            email: "rekey307@example.test",
            name: "Rekey307",
            avatarUrl: nil
        )
        await Task.yield()

        // Session ID must be migrated to the real user key and old key cleared
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: realKey),
            "sess-rekey-307",
            "session ID must be re-keyed to the real user's storage key"
        )
        XCTAssertNil(
            UserDefaults.standard.string(forKey: unknownKey),
            "unknown key must be cleared after re-keying"
        )
    }

    func testSessionIdReloadsWhenUserProfileArrivesAfterInit() async {
        let userId = "user_ama2123_cold_start"
        let storageKey = "coach_chat_session_id_\(userId)"
        let unknownKey = "coach_chat_session_id_unknown"
        UserDefaults.standard.set("sess-after-profile", forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: unknownKey)
        defer {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: unknownKey)
        }

        let pairingService = MockPairingService()
        pairingService.storedToken = "test-jwt-token"
        pairingService.isPaired = true
        pairingService.userProfile = nil
        let dependencies = AppDependencies(
            apiService: MockAPIService(),
            pairingService: pairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService(),
            coachSessionClient: MockCoachSessionClient()
        )

        let lateProfileViewModel = CoachViewModel(dependencies: dependencies)
        XCTAssertNil(lateProfileViewModel.sessionId)

        pairingService.userProfile = UserProfile(
            id: userId,
            email: "ama2123@example.test",
            name: "AMA2123",
            avatarUrl: nil
        )

        await Task.yield()
        XCTAssertEqual(lateProfileViewModel.sessionId, "sess-after-profile")
    }
}
