//
//  CoachFirstTokenStreamingTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2233 (E9-7): first-token SLO instrumentation and streaming lifecycle.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class CoachFirstTokenStreamingTests: XCTestCase {
    private var stream: MockChatStreamService!
    private var session: MockCoachSessionClient!
    private var pairing: MockPairingService!
    private var pendingClient: MockPendingActionsClient!
    private var userId: String!

    override func setUp() async throws {
        stream = MockChatStreamService()
        session = MockCoachSessionClient()
        pairing = MockPairingService()
        pendingClient = MockPendingActionsClient()
        userId = "first-token-\(UUID().uuidString)"
        pairing.configurePaired(token: "test-token", userId: userId)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.coachSessionID(userID: userId))
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.coachSessionID(userID: userId))
    }

    private func makeViewModel(
        isMockCoachPath: Bool = false,
        telemetrySink: CoachTurnTelemetryProviding = CapturingTelemetrySink()
    ) -> CoachViewModel {
        CoachViewModel(dependencies: AppDependencies(
            apiService: MockAPIService(),
            pairingService: pairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: stream,
            coachSessionClient: session,
            pendingActionsClient: pendingClient,
            coachTurnTelemetrySink: telemetrySink,
            isMockCoachPath: isMockCoachPath
        ))
    }

    func testFirstTokenTimingIsRecordedForCoachTurn() async {
        let viewModel = makeViewModel()
        stream.eventsToYield = [
            .messageStart(sessionId: "s-first-token", traceId: "trace-first-token"),
            .firstToken(latencyMs: 487, sourceStage: "llm", mode: "live"),
            .contentDelta(text: "Keep it easy."),
            .messageEnd(sessionId: "s-first-token", tokensUsed: 9, latencyMs: 900)
        ]

        await viewModel.sendMessage("How hard should today be?")

        let assistant = viewModel.messages.last
        XCTAssertNotNil(assistant?.firstTokenLatencyMs)
        XCTAssertGreaterThanOrEqual(assistant?.firstTokenLatencyMs ?? -1, 0)
        let firstTokenEvent = viewModel.coachTurnTelemetryEvents.first(where: { $0.name == .firstToken })
        XCTAssertNotNil(firstTokenEvent?.latencyMs)
        XCTAssertGreaterThanOrEqual(firstTokenEvent?.latencyMs ?? -1, 0)
        XCTAssertEqual(firstTokenEvent?.details, "First token received (source_latency_ms=487)")
        XCTAssertEqual(firstTokenEvent?.mode, .live)
        XCTAssertEqual(firstTokenEvent?.sourceStage, .llm)
    }

    func testStreamingLifecycleRendersInOrderAndFailureShowsRetry() async {
        let successVM = makeViewModel()
        stream.eventsToYield = [
            .messageStart(sessionId: "s-stream", traceId: nil),
            .contentDelta(text: "First "),
            .contentDelta(text: "partial"),
            .messageEnd(sessionId: "s-stream", tokensUsed: 10, latencyMs: 120)
        ]

        await successVM.sendMessage("Stream a response")

        XCTAssertEqual(successVM.streamingLifecycle, [
            .waiting,
            .firstTokenReceived,
            .partialResponse,
            .completed
        ])
        XCTAssertEqual(successVM.messages.last?.streamingPhase, .completed)

        let failureVM = makeViewModel()
        stream.eventsToYield = [
            .error(type: "llm_unavailable", message: "LLM dependency down", usage: nil, limit: nil)
        ]

        await failureVM.sendMessage("Fail this turn")

        XCTAssertNil(failureVM.messages.last?.streamingPhase)
        XCTAssertEqual(failureVM.streamingLifecycle, [.waiting, .failed])
        XCTAssertTrue(failureVM.error?.isRetryable ?? false)
        XCTAssertEqual(failureVM.degradeMode, .manual)
    }

    func testTelemetryDistinguishesLiveMockSkipAndDataGapModes() async {
        let liveVM = makeViewModel()
        stream.eventsToYield = [
            .messageStart(sessionId: "s-live", traceId: nil),
            .contentDelta(text: "Live reply"),
            .messageEnd(sessionId: "s-live", tokensUsed: 3, latencyMs: 20)
        ]
        await liveVM.sendMessage("Live")
        XCTAssertEqual(liveVM.coachTurnTelemetryEvents.first(where: { $0.name == .firstToken })?.mode, .live)

        let mockVM = makeViewModel(isMockCoachPath: true)
        stream.eventsToYield = [
            .messageStart(sessionId: "s-mock", traceId: nil),
            .contentDelta(text: "Mock reply"),
            .messageEnd(sessionId: "s-mock", tokensUsed: 3, latencyMs: 20)
        ]
        await mockVM.sendMessage("Mock")
        XCTAssertEqual(mockVM.coachTurnTelemetryEvents.first(where: { $0.name == .sendStarted })?.mode, .mock)

        pairing.storedToken = nil
        let skipVM = makeViewModel()
        await skipVM.sendMessage("Skip")
        XCTAssertEqual(skipVM.coachTurnTelemetryEvents.first(where: { $0.name == .failed })?.mode, .skip)

        pairing.storedToken = "test-token"
        let dataGapVM = makeViewModel()
        stream.errorToThrow = URLError(.cannotConnectToHost)
        await dataGapVM.sendMessage("Data gap")
        XCTAssertEqual(dataGapVM.coachTurnTelemetryEvents.first(where: { $0.name == .failed })?.mode, .dataGap)
    }

    func testStreamingDoesNotBypassPendingActionOrVoiceFallback() async {
        let viewModel = makeViewModel()
        stream.eventsToYield = [
            .messageStart(sessionId: "s-pa", traceId: nil),
            .contentDelta(text: "I need approval first."),
            .functionResult(toolUseId: "tool-1", name: "coach_execute", result: pendingActionCreatedJSON(actionId: "pa_stream_guard")),
            .messageEnd(sessionId: "s-pa", tokensUsed: 14, latencyMs: 160)
        ]

        await viewModel.submitVoiceTranscript("Move my workout", speakResponse: false)

        XCTAssertTrue(pendingClient.confirmationRequests.isEmpty, "streaming must surface PendingActions without approving them")
        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.executionStatus, .pending)
        XCTAssertTrue(viewModel.voiceState.textResponseVisible)
        XCTAssertTrue(viewModel.voiceState.pendingActionConfirmationVisible)
        XCTAssertEqual(viewModel.coachTurnTelemetryEvents.first(where: { $0.name == .pendingActionSurfaced })?.sourceStage, .coachCore)
    }

    func testDependencyDownAndTelemetrySinkDownDegradeWithoutCrash() async {
        let viewModel = makeViewModel(telemetrySink: ThrowingTelemetrySink())
        stream.errorToThrow = URLError(.timedOut)

        let accepted = await viewModel.sendMessage("Timeout")

        XCTAssertFalse(accepted)
        XCTAssertEqual(viewModel.degradeMode, .manual)
        XCTAssertEqual(viewModel.telemetrySinkMode, .dataGap)
        XCTAssertTrue(viewModel.coachTurnTelemetryEvents.contains { $0.name == .telemetrySinkDown })
        XCTAssertTrue(viewModel.error?.isRetryable ?? false)
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
              "target": "session:intervals-42",
              "workout_id": "wrk_intervals_42",
              "date": "2026-06-28"
            },
            "idempotency_key": "pending-action:v1:ama-2233"
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

private struct CapturingTelemetrySink: CoachTurnTelemetryProviding {
    @MainActor
    func emit(_ event: CoachTurnTelemetryEvent) throws {}
}

private struct ThrowingTelemetrySink: CoachTurnTelemetryProviding {
    struct SinkDown: LocalizedError {
        var errorDescription: String? { "metrics sink down" }
    }

    @MainActor
    func emit(_ event: CoachTurnTelemetryEvent) throws {
        throw SinkDown()
    }
}
