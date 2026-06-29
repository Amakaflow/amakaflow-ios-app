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

    override func setUp() async throws {
        mockStreamService = MockChatStreamService()
        mockSessionClient = MockCoachSessionClient()
        mockPairingService = MockPairingService()
        mockPairingService.storedToken = "test-jwt-token"
        mockPairingService.isPaired = true
    }

    /// Build a view model whose coach turns are served by the injected
    /// (shared-path) stream/session doubles. `isMockCoachPath` mirrors the
    /// fixture/dev wiring; default `false` exercises the live-path contract.
    private func makeViewModel(isMockCoachPath: Bool = false) -> CoachViewModel {
        let dependencies = AppDependencies(
            apiService: MockAPIService(),
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: mockStreamService,
            coachSessionClient: mockSessionClient,
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

    func testStaleSessionRestore404IsNotADegradation() async {
        let viewModel = makeViewModel()
        viewModel.sessionId = "stale-session"
        mockSessionClient.errorToThrow = CoachSessionError.sessionNotFound

        await viewModel.loadMessagesIfNeeded()

        XCTAssertNil(viewModel.sessionId, "404 clears the stale session id (new conversation)")
        XCTAssertNil(viewModel.degradeMode, "a 404/new-conversation is normal, not degraded")
        XCTAssertTrue(viewModel.messages.isEmpty)
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
}
