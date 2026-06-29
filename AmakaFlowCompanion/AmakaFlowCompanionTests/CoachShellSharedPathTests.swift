//
//  CoachShellSharedPathTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2234 (E9-3): the single in-app coach UI shell must route every turn
//  through the shared mobile-BFF / Channel Gateway / coach core session path
//  (no duplicate iOS coach brain), preserve session continuity/restore, and
//  degrade missing dependencies to text/manual/mock/skip/data_gap — never a
//  crash, blank screen, or silent success.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class CoachShellSharedPathTests: XCTestCase {

    private var mockStreamService: MockChatStreamService!
    private var mockSessionClient: MockCoachSessionClient!
    private var mockPairingService: MockPairingService!
    private var testUserId: String!

    override func setUp() async throws {
        mockStreamService = MockChatStreamService()
        mockSessionClient = MockCoachSessionClient()
        mockPairingService = MockPairingService()
        mockPairingService.storedToken = "test-jwt-token"
        mockPairingService.isPaired = true
        // CoachViewModel.init reloads sessionId from UserDefaults.standard and
        // streamed turns write it back, so give each test a unique per-user
        // session key to keep the suite order-independent.
        testUserId = "coach-shell-test-\(UUID().uuidString)"
        mockPairingService.userProfile = UserProfile(id: testUserId, email: nil, name: nil, avatarUrl: nil)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.coachSessionID(userID: testUserId))
    }

    override func tearDown() async throws {
        if let testUserId {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.coachSessionID(userID: testUserId))
        }
    }

    /// Build a view model whose coach turns are served by the injected
    /// (shared-path) stream/session doubles. `isMockCoachPath` mirrors the
    /// fixture/dev wiring; default `false` exercises the live-path contract.
    private func makeViewModel(
        isMockCoachPath: Bool = false,
        sessionClient: CoachSessionProviding? = nil,
        audioService: AudioProviding = MockAudioService(),
        pendingActionsClient: PendingActionsProviding = MockPendingActionsClient()
    ) -> CoachViewModel {
        let dependencies = AppDependencies(
            apiService: MockAPIService(),
            pairingService: mockPairingService,
            audioService: audioService,
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: mockStreamService,
            coachSessionClient: sessionClient ?? mockSessionClient,
            pendingActionsClient: pendingActionsClient,
            isMockCoachPath: isMockCoachPath
        )
        return CoachViewModel(dependencies: dependencies)
    }

    // MARK: - Shared path / no duplicate brain

    func testAppTurnRoutesThroughSharedStreamPathNotLocalBrain() async {
        let viewModel = makeViewModel()
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "shared-session-1", traceId: "trace-1"),
            .contentDelta(text: "Server-built "),
            .contentDelta(text: "coach reply"),
            .messageEnd(sessionId: "shared-session-1", tokensUsed: 12, latencyMs: 120)
        ]

        await viewModel.sendMessage("What pace today?")

        // The turn must be served by the injected shared ChatStreamService
        // (mobile-bff `/v1/chat/stream`), not generated locally.
        XCTAssertTrue(mockStreamService.streamCalled, "turn must route through the shared BFF/gateway stream path")
        // Assistant content is exactly what the shared path streamed — the app
        // does not author or rewrite the reply (no local coach brain).
        XCTAssertEqual(viewModel.messages.last?.content, "Server-built coach reply")
        // Session id is owned by the server/shared core, adopted from the stream.
        XCTAssertEqual(viewModel.sessionId, "shared-session-1")
    }

    func testHealthyLiveTurnIsNotDegraded() async {
        let viewModel = makeViewModel()
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "All good"),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]

        await viewModel.sendMessage("Hi coach")

        XCTAssertNil(viewModel.degradeMode, "a healthy live turn must not be flagged degraded")
        XCTAssertFalse(viewModel.degradeMode?.isDegraded ?? false)
    }

    // MARK: - Voice input/output contract

    func testVoiceInputYieldsTextBeforeSharedCoachSessionPath() async {
        let viewModel = makeViewModel()
        viewModel.startVoiceListening(partialTranscript: "Move my long run to Saturday", durationLabel: "0:06")
        viewModel.updateVoicePartialTranscript("Move my long run to Saturday and make today easy")
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "voice-shared-session", traceId: "voice-trace"),
            .contentDelta(text: "Done as a proposal."),
            .messageEnd(sessionId: "voice-shared-session", tokensUsed: 8, latencyMs: 80)
        ]

        let accepted = await viewModel.submitVoiceTranscript(speakResponse: false)

        XCTAssertTrue(accepted)
        XCTAssertTrue(mockStreamService.streamCalled, "voice must enter the same shared stream path as typed text")
        XCTAssertEqual(mockStreamService.lastRequest?.message, "Move my long run to Saturday and make today easy")
        XCTAssertEqual(viewModel.voiceState.lastSubmittedTranscript, "Move my long run to Saturday and make today easy")
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertEqual(viewModel.messages.first?.content, "Move my long run to Saturday and make today easy")
    }

    func testSpokenOutputNeverSuppressesTextOrPendingActionConfirmation() async {
        let audio = MockAudioService()
        let viewModel = makeViewModel(audioService: audio)
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "voice-pa-session", traceId: "voice-pa-trace"),
            .contentDelta(text: "I can move it, but approve first."),
            .functionResult(
                toolUseId: "pa-tool",
                name: "coach_execute",
                result: pendingActionCreatedJSON(actionId: "pa_voice_requires_approval")
            ),
            .messageEnd(sessionId: "voice-pa-session", tokensUsed: 12, latencyMs: 95)
        ]

        let accepted = await viewModel.submitVoiceTranscript("Move my threshold run", speakResponse: true)

        XCTAssertTrue(accepted)
        XCTAssertTrue(audio.speakCalled, "spoken output may play, but only after text is present")
        XCTAssertEqual(audio.lastSpokenText, "I can move it, but approve first.")
        XCTAssertEqual(viewModel.messages.last?.content, "I can move it, but approve first.")
        XCTAssertEqual(viewModel.messages.last?.pendingActions.first?.actionId, "pa_voice_requires_approval")
        XCTAssertEqual(viewModel.messages.last?.pendingActions.first?.executionStatus, .pending)
        XCTAssertTrue(viewModel.voiceState.textResponseVisible)
        XCTAssertTrue(viewModel.voiceState.pendingActionConfirmationVisible)
    }

    func testVoiceDependencyFailuresMapToExplicitFallbacks() {
        let expectations: [(CoachVoiceDependency, CoachDegradeMode, String, CoachVoicePhase)] = [
            (.permissionDenied, .manual, "manual", .transcriptionFallback),
            (.recorderUnavailable, .mock, "mock", .transcriptionFallback),
            (.sttDown, .manual, "manual", .transcriptionFallback),
            (.networkDown, .manual, "manual", .transcriptionFallback),
            (.gatewayDown, .dataGap, "data_gap", .transcriptionFallback)
        ]

        for (dependency, mode, action, phase) in expectations {
            let state = CoachVoiceState(
                phase: phase,
                partialTranscript: "fixture phrase",
                manualTranscript: "fixture phrase",
                durationLabel: "0:06",
                savedRecordingLabel: "0:06",
                dependency: dependency,
                textResponseVisible: true,
                pendingActionConfirmationVisible: true
            )

            XCTAssertEqual(state.phase, phase, "\(dependency.rawValue) should render a visible fallback")
            XCTAssertEqual(state.fallbackMode.contractToken, mode.contractToken)
            XCTAssertEqual(state.fallbackAction, action)
            XCTAssertTrue(state.textResponseVisible)
            XCTAssertTrue(state.pendingActionConfirmationVisible)
        }

        let ttsState = CoachVoiceState(
            phase: .degraded,
            dependency: .ttsDown,
            textResponseVisible: true,
            pendingActionConfirmationVisible: true
        )

        XCTAssertEqual(ttsState.phase, .degraded)
        XCTAssertEqual(ttsState.fallbackMode.contractToken, CoachDegradeMode.skip.contractToken)
        XCTAssertEqual(ttsState.fallbackAction, "skip")
        XCTAssertTrue(ttsState.textResponseVisible, "TTS down must skip speech while keeping text visible")
    }

    func testVoiceTranscriptCannotAutoApprovePendingAction() async {
        let pendingClient = MockPendingActionsClient()
        let viewModel = makeViewModel(pendingActionsClient: pendingClient)
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "voice-no-auto-approve", traceId: nil),
            .contentDelta(text: "Here is a proposed change."),
            .functionResult(
                toolUseId: "pa-tool",
                name: "coach_execute",
                result: pendingActionCreatedJSON(actionId: "pa_voice_no_auto_approve")
            ),
            .messageEnd(sessionId: "voice-no-auto-approve", tokensUsed: 10, latencyMs: 70)
        ]

        await viewModel.submitVoiceTranscript("Yes move it", speakResponse: false)

        XCTAssertTrue(pendingClient.confirmationRequests.isEmpty, "voice input is a message, not approval")
        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.actionId, "pa_voice_no_auto_approve")
        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.executionStatus, .pending)
    }

    // MARK: - Session continuity / restore

    func testSessionRestoreUsesSharedSessionClientAndStaysHealthy() async {
        let viewModel = makeViewModel()
        viewModel.sessionId = "continued-session"
        mockSessionClient.messagesToReturn = [
            RestoredSessionMessage(role: .user, content: "Earlier question", timestamp: Date(timeIntervalSince1970: 1_700_000_000)),
            RestoredSessionMessage(role: .assistant, content: "Earlier answer", timestamp: Date(timeIntervalSince1970: 1_700_000_030))
        ]

        await viewModel.loadMessagesIfNeeded()

        XCTAssertTrue(mockSessionClient.fetchCalled, "restore must use the shared session client (BFF session messages)")
        XCTAssertEqual(mockSessionClient.lastSessionId, "continued-session")
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertTrue(viewModel.didRestoreConversation)
        XCTAssertNil(viewModel.degradeMode, "successful restore resolves to a healthy state")
    }

    func testSessionRestoreFailureDegradesToDataGapNotFabricated() async {
        let viewModel = makeViewModel()
        viewModel.sessionId = "broken-session"
        mockSessionClient.errorToThrow = CoachSessionError.httpError(statusCode: 500, body: "boom")

        await viewModel.loadMessagesIfNeeded()

        XCTAssertEqual(viewModel.degradeMode, .dataGap, "history that can't be loaded must surface data_gap, not guessed content")
        XCTAssertEqual(viewModel.degradeMode?.contractToken, "data_gap")
        XCTAssertNotNil(viewModel.restoreError)
        XCTAssertTrue(viewModel.messages.isEmpty, "must not fabricate restored messages on failure")
    }

    func testStartNewChatDuringRestoreIgnoresLateCompletion() async {
        let suspending = SuspendingCoachSessionClient()
        suspending.messagesToReturn = [
            RestoredSessionMessage(role: .assistant, content: "stale history", timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        ]
        let viewModel = makeViewModel(sessionClient: suspending)
        viewModel.sessionId = "to-be-abandoned"

        // Restore starts and suspends inside fetchMessages.
        let restoreTask = Task { await viewModel.loadMessagesIfNeeded() }
        await fulfillment(of: [suspending.entered], timeout: 2.0)

        // User starts a brand-new chat while the restore is still in flight.
        viewModel.startNewChat()

        // Now let the stale restore complete.
        suspending.release()
        await restoreTask.value

        XCTAssertTrue(viewModel.messages.isEmpty, "a late restore must not repopulate a thread cleared by New Chat")
        XCTAssertNil(viewModel.sessionId, "New Chat cleared the session; the stale restore must not revive it")
        XCTAssertNil(viewModel.degradeMode, "the fresh thread stays healthy, not re-degraded by the stale restore")
        XCTAssertFalse(viewModel.didRestoreConversation, "the abandoned restore must not flag a restored conversation")
    }

    func testStaleSessionRestore404IsNotADegradation() async {
        let viewModel = makeViewModel()
        viewModel.sessionId = "stale-session"
        mockSessionClient.errorToThrow = CoachSessionError.sessionNotFound

        await viewModel.loadMessagesIfNeeded()

        XCTAssertNil(viewModel.sessionId, "404 clears the stale session id (new conversation)")
        XCTAssertNil(viewModel.degradeMode, "a 404/new-conversation is normal, not degraded")
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testDataGapClearsOnRetryThatReturnsEmpty() async {
        let viewModel = makeViewModel()
        viewModel.sessionId = "recovering-session"
        // First restore fails (server 500) → data_gap.
        mockSessionClient.errorToThrow = CoachSessionError.httpError(statusCode: 500, body: "boom")
        await viewModel.loadMessagesIfNeeded()
        XCTAssertEqual(viewModel.degradeMode, .dataGap)

        // Shared path recovers but the session legitimately has no history yet.
        mockSessionClient.errorToThrow = nil
        mockSessionClient.messagesToReturn = []
        await viewModel.retryLoadMessages()

        XCTAssertNil(viewModel.degradeMode, "a successful (empty) retry must clear the prior data_gap")
        XCTAssertNil(viewModel.restoreError)
        XCTAssertTrue(viewModel.messages.isEmpty, "an empty thread is not fabricated, and not stuck degraded")
    }

    func testDataGapClearsOnRetryThatReturns404() async {
        let viewModel = makeViewModel()
        viewModel.sessionId = "recovering-session"
        mockSessionClient.errorToThrow = CoachSessionError.httpError(statusCode: 503, body: "unavailable")
        await viewModel.loadMessagesIfNeeded()
        XCTAssertEqual(viewModel.degradeMode, .dataGap)

        // Retry now resolves the session as gone → normal new-conversation.
        mockSessionClient.errorToThrow = CoachSessionError.sessionNotFound
        await viewModel.retryLoadMessages()

        XCTAssertNil(viewModel.degradeMode, "a 404 on retry is a new conversation, not a lingering data_gap")
        XCTAssertNil(viewModel.sessionId, "the stale session id is cleared on 404")
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testSendIsRejectedWhileSessionRestoreInFlight() async {
        let viewModel = makeViewModel()
        // Simulate restore still running: loadMessagesIfNeeded() snapshots
        // messages.isEmpty before its await and replaces messages on completion,
        // so a send during this window would be clobbered.
        viewModel.isLoadingMessages = true

        await viewModel.sendMessage("Sneak a message in during restore")

        XCTAssertFalse(mockStreamService.streamCalled, "send must be rejected while restore is in flight")
        XCTAssertTrue(viewModel.messages.isEmpty, "no turn is started until restore settles")
        XCTAssertFalse(viewModel.isStreaming)
    }

    // MARK: - Dependency-down degradation (not crash / blank / silent success)

    func testTransportDownDegradesToManualTextOnly() async {
        let viewModel = makeViewModel()
        // BFF / Channel Gateway unreachable.
        mockStreamService.errorToThrow = URLError(.cannotConnectToHost)

        await viewModel.sendMessage("Are you there?")

        XCTAssertEqual(viewModel.degradeMode, .manual, "an unreachable shared path degrades to text-only manual mode")
        XCTAssertEqual(viewModel.degradeMode?.contractToken, "manual")
        XCTAssertTrue(viewModel.degradeMode?.isDegraded ?? false)
        XCTAssertTrue(viewModel.error?.isRetryable ?? false, "transient transport failure must offer retry")
        XCTAssertTrue(viewModel.messages.isEmpty, "no half-sent bubble left behind — not a blank/partial crash state")
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testServerSideCoachUnavailableEventDegradesToManual() async {
        let viewModel = makeViewModel()
        // Shared core / LLM reports it can't serve the turn (SSE error event).
        mockStreamService.eventsToYield = [
            .error(type: "coach_unavailable", message: "Coach is offline", usage: nil, limit: nil)
        ]

        await viewModel.sendMessage("Plan my week")

        XCTAssertEqual(viewModel.degradeMode, .manual)
        XCTAssertNotNil(viewModel.error, "the failure is surfaced, never a silent success")
    }

    func testRateLimitIsNotTreatedAsDependencyDegradation() async {
        let viewModel = makeViewModel()
        mockStreamService.eventsToYield = [
            .error(type: "rate_limit_exceeded", message: "Too many requests", usage: 50, limit: 50)
        ]

        await viewModel.sendMessage("Hello")

        XCTAssertEqual(viewModel.rateLimitInfo?.usage, 50)
        XCTAssertNil(viewModel.degradeMode, "rate limiting is a usage cap, not a degraded shared path")
    }

    func testRecoveryAfterManualDegradeReturnsToHealthy() async {
        let viewModel = makeViewModel()
        mockStreamService.errorToThrow = URLError(.timedOut)
        await viewModel.sendMessage("First try")
        XCTAssertEqual(viewModel.degradeMode, .manual)

        // Shared path recovers.
        mockStreamService.errorToThrow = nil
        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Back online"),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]
        await viewModel.retryLastMessage()

        XCTAssertNil(viewModel.degradeMode, "a successful retry clears the degraded state")
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Stop affordance cleanup

    func testCancelBeforeFirstTokenRemovesEmptyAssistantPlaceholder() async {
        let viewModel = makeViewModel()
        let userMessage = ChatMessage(role: .user, content: "Plan my week")
        let pendingAssistant = ChatMessage(role: .assistant, content: "", isStreaming: true)
        viewModel.messages = [userMessage, pendingAssistant]

        viewModel.cancelStream()

        // The user's message stays; the blank assistant placeholder is removed
        // (Stop during the first-token wait must not leave an empty bubble).
        XCTAssertEqual(viewModel.messages.map(\.role), [.user])
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testCancelAfterFirstTokenKeepsPartialAssistantReply() async {
        let viewModel = makeViewModel()
        let userMessage = ChatMessage(role: .user, content: "Plan my week")
        let partialAssistant = ChatMessage(role: .assistant, content: "Here's a start", isStreaming: true)
        viewModel.messages = [userMessage, partialAssistant]

        viewModel.cancelStream()

        // Partial content is real coach output — keep it, just stop streaming.
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.last?.content, "Here's a start")
        XCTAssertFalse(viewModel.messages.last?.isStreaming ?? true)
    }

    // MARK: - Mock/dev fixture mode is sticky and honest

    func testMockCoachPathIsStickyMockOnSuccess() async {
        let viewModel = makeViewModel(isMockCoachPath: true)
        XCTAssertEqual(viewModel.degradeMode, .mock, "fixture/dev wiring starts in honest mock mode")

        mockStreamService.eventsToYield = [
            .messageStart(sessionId: "s1", traceId: nil),
            .contentDelta(text: "Fixture reply"),
            .messageEnd(sessionId: "s1", tokensUsed: 5, latencyMs: 50)
        ]
        await viewModel.sendMessage("Hi")

        XCTAssertEqual(viewModel.degradeMode, .mock, "mock mode reflects the environment and stays sticky after a turn")
    }

    func testMockCoachPathStaysMockEvenOnFailure() async {
        let viewModel = makeViewModel(isMockCoachPath: true)
        mockStreamService.errorToThrow = URLError(.cannotConnectToHost)

        await viewModel.sendMessage("Hi")

        XCTAssertEqual(viewModel.degradeMode, .mock, "a failure in mock mode stays mock, not manual")
    }

    func testStartNewChatResetsDegradeToBaseline() async {
        let viewModel = makeViewModel()
        mockStreamService.errorToThrow = URLError(.notConnectedToInternet)
        await viewModel.sendMessage("Offline send")
        XCTAssertEqual(viewModel.degradeMode, .manual)

        viewModel.startNewChat()

        XCTAssertNil(viewModel.degradeMode, "new chat returns to the dependency baseline")
    }

    // MARK: - Contract guard

    func testDegradeModeContractTokensMatchVoiceContract() {
        XCTAssertEqual(CoachDegradeMode.text.contractToken, "text")
        XCTAssertEqual(CoachDegradeMode.manual.contractToken, "manual")
        XCTAssertEqual(CoachDegradeMode.mock.contractToken, "mock")
        XCTAssertEqual(CoachDegradeMode.skip.contractToken, "skip")
        XCTAssertEqual(CoachDegradeMode.dataGap.contractToken, "data_gap")
        // Only `.text` is non-degraded; every other mode lights the health dot.
        XCTAssertFalse(CoachDegradeMode.text.isDegraded)
        for mode in CoachDegradeMode.allCases where mode != .text {
            XCTAssertTrue(mode.isDegraded, "\(mode) should render as degraded")
        }
    }

    private func pendingActionCreatedJSON(actionId: String) -> String {
        """
        {
          "status": "pending_action_created",
          "mode": "mock",
          "action": {
            "action_id": "\(actionId)",
            "tool_name": "propose_schedule_workout",
            "risk_tier": "medium",
            "execution_status": "pending",
            "channel": "app",
            "normalized_payload": {
              "target": "session:threshold-thu",
              "workout_id": "wrk_threshold_42",
              "date": "2026-06-29"
            },
            "idempotency_key": "pending-action:v1:voice-test"
          },
          "side_effect_count": 0,
          "dependency_status": {
            "supabase": "mock",
            "redis_iris": "skip",
            "llm": "skip"
          }
        }
        """
    }
}

/// A session client whose `fetchMessages` suspends until `release()` is called,
/// so a test can interleave another action (e.g. `startNewChat()`) with an
/// in-flight restore and then let the stale completion land.
@MainActor
private final class SuspendingCoachSessionClient: CoachSessionProviding {
    var messagesToReturn: [RestoredSessionMessage] = []
    let entered = XCTestExpectation(description: "fetchMessages entered")
    private var continuation: CheckedContinuation<Void, Never>?

    func fetchMessages(sessionId: String, limit: Int, token: String) async throws -> [RestoredSessionMessage] {
        entered.fulfill()
        await withCheckedContinuation { continuation = $0 }
        return messagesToReturn
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class CoachKnowledgeSurfaceTests: XCTestCase {

    func testReadableSectionsRenderBeforeAtomicClaimDetail() async {
        let api = MockAPIService()
        let viewModel = CoachKnowledgeViewModel(apiService: api)

        await viewModel.load()

        XCTAssertTrue(api.fetchCoachKnowledgeSurfaceCalled)
        XCTAssertEqual(viewModel.surface?.readableOrder.first, "sections")
        XCTAssertEqual(viewModel.surface?.readableOrder.dropFirst().first, "provenance")
        XCTAssertEqual(viewModel.surfaceContentOrder.first, "readable_sections")
        XCTAssertEqual(viewModel.surfaceContentOrder.dropFirst().first, "attention_banners")
        XCTAssertEqual(viewModel.surface?.sections.first?.title, "Goals")
        XCTAssertEqual(viewModel.acceptedFacts.first?.text, "HYROX race - May 2026")
    }

    func testReadableSectionsExcludeNeedsReviewFactsFromAcceptedTruthRows() async throws {
        let api = MockAPIService()
        let base = CoachKnowledgeSurface.ama2229Fixture
        let accepted = try XCTUnwrap(base.sections.first?.facts.first)
        let heldFact = CoachKnowledgeFact(
            id: "fact-held-in-section",
            text: "Possible left knee issue",
            state: "needs_review",
            category: "Injury",
            confidence: 0.6,
            sensitivity: "sensitive_health",
            source: accepted.source,
            provenance: []
        )
        let mixedSection = CoachKnowledgeSection(
            id: "mixed-health",
            title: "Health & recovery",
            summary: "",
            facts: [heldFact, accepted]
        )
        api.fetchCoachKnowledgeSurfaceResult = .success(
            CoachKnowledgeSurface(
                mode: base.mode,
                readableOrder: base.readableOrder,
                sections: [mixedSection],
                sensitivePending: base.sensitivePending,
                contradictions: base.contradictions,
                dataGaps: base.dataGaps,
                contract: base.contract
            )
        )
        let viewModel = CoachKnowledgeViewModel(apiService: api)

        await viewModel.load()

        XCTAssertEqual(viewModel.visibleReadableSections.first?.facts.map(\.id), ["fact-goal"])
        XCTAssertFalse(viewModel.acceptedFacts.contains { $0.id == "fact-held-in-section" })
    }

    func testAcceptedFactsKeepSourceAndDrillableProvenance() async throws {
        let viewModel = CoachKnowledgeViewModel(apiService: MockAPIService())

        await viewModel.load()

        let fact = try XCTUnwrap(viewModel.acceptedFacts.first(where: { !$0.provenance.isEmpty }))
        XCTAssertEqual(fact.state, "accepted")
        XCTAssertEqual(fact.source?.label, "You told me")
        XCTAssertEqual(fact.provenance.first?.quote, "HYROX in May.")
    }

    func testSensitiveNeedsReviewFactsAreReviewOnlyNeverAcceptedTruth() async {
        let viewModel = CoachKnowledgeViewModel(apiService: MockAPIService())

        await viewModel.load()

        XCTAssertFalse(viewModel.acceptedFacts.contains { $0.text == "Possible left knee issue" })
        XCTAssertEqual(viewModel.reviewOnlyFacts.first?.state, "needs_review")
        XCTAssertEqual(viewModel.reviewOnlyFacts.first?.heldLabel, "HELD · NOT APPLIED")
        XCTAssertTrue(viewModel.reviewOnlyFacts.allSatisfy(\.isReviewOnly))
    }

    func testReviewActionsHitSharedCoachWikiPendingActionsPath() async throws {
        let api = MockAPIService()
        let viewModel = CoachKnowledgeViewModel(apiService: api)
        await viewModel.load()
        let fact = try XCTUnwrap(viewModel.reviewOnlyFacts.first)

        await viewModel.reviewSensitiveFact(fact, decision: .approve)

        XCTAssertTrue(api.reviewCoachKnowledgeCalled)
        XCTAssertEqual(api.reviewCoachKnowledgeActionId, "pa-knee-review")
        XCTAssertEqual(api.reviewCoachKnowledgeDecision, .approve)
        XCTAssertEqual(api.reviewCoachKnowledgeReason, "Approved from iOS CKW surface.")
    }

    func testRejectReviewActionsHitSharedCoachWikiPendingActionsPath() async throws {
        let api = MockAPIService()
        let viewModel = CoachKnowledgeViewModel(apiService: api)
        await viewModel.load()
        let fact = try XCTUnwrap(viewModel.reviewOnlyFacts.first)

        await viewModel.reviewSensitiveFact(fact, decision: .reject)

        XCTAssertTrue(api.reviewCoachKnowledgeCalled)
        XCTAssertEqual(api.reviewCoachKnowledgeActionId, "pa-knee-review")
        XCTAssertEqual(api.reviewCoachKnowledgeDecision, .reject)
        XCTAssertEqual(api.reviewCoachKnowledgeReason, "Kept private from iOS CKW surface.")
    }

    func testDuplicateSensitiveReviewSubmissionsAreBlockedPerAction() async throws {
        let api = MockAPIService()
        api.reviewCoachKnowledgeDelayNanoseconds = 100_000_000
        let viewModel = CoachKnowledgeViewModel(apiService: api)
        await viewModel.load()
        let fact = try XCTUnwrap(viewModel.reviewOnlyFacts.first)

        async let first: Void = viewModel.reviewSensitiveFact(fact, decision: .approve)
        async let second: Void = viewModel.reviewSensitiveFact(fact, decision: .reject)
        _ = await (first, second)

        XCTAssertEqual(api.reviewCoachKnowledgeCallCount, 1)
    }

    func testMultipleContradictionsRemainAvailableForResolveSurface() async throws {
        let api = MockAPIService()
        let base = CoachKnowledgeSurface.ama2229Fixture
        let first = try XCTUnwrap(base.contradictions.first)
        let second = CoachKnowledgeContradiction(
            id: "contradiction-training-source",
            state: "needs_user_review",
            claimIdA: "threshold-chat",
            claimIdB: "threshold-device",
            options: first.options
        )
        api.fetchCoachKnowledgeSurfaceResult = .success(
            CoachKnowledgeSurface(
                mode: base.mode,
                readableOrder: base.readableOrder,
                sections: base.sections,
                sensitivePending: base.sensitivePending,
                contradictions: [first, second],
                dataGaps: base.dataGaps,
                contract: base.contract
            )
        )
        let viewModel = CoachKnowledgeViewModel(apiService: api)

        await viewModel.load()

        XCTAssertEqual(viewModel.surface?.contradictions.map(\.id), ["contradiction-knee", "contradiction-training-source"])
        XCTAssertEqual(viewModel.surface?.contradictions.flatMap { $0.options ?? [] }.count, 4)
    }

    func testDependencyDownDegradesToDataGapWithoutFabricatedKnowledge() async {
        let api = MockAPIService()
        api.fetchCoachKnowledgeSurfaceResult = .failure(APIError.networkError(URLError(.notConnectedToInternet)))
        let viewModel = CoachKnowledgeViewModel(apiService: api)

        await viewModel.load()

        XCTAssertEqual(viewModel.surface?.mode, "data_gap")
        XCTAssertTrue(viewModel.acceptedFacts.isEmpty)
        XCTAssertEqual(viewModel.surface?.dataGaps.first?.id, "ios-ckw-bff-unavailable")
        XCTAssertTrue(viewModel.surface?.dataGaps.first?.detail.contains("No accepted knowledge was fabricated") ?? false)
    }
}
