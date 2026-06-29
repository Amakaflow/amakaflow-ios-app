//
//  CoachPendingActionsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2230 (E9-4): PendingActions confirmation surface + shared execute path.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class CoachPendingActionsTests: XCTestCase {
    private var stream: MockChatStreamService!
    private var session: MockCoachSessionClient!
    private var pendingClient: MockPendingActionsClient!
    private var pairing: MockPairingService!
    private var userId: String!

    override func setUp() async throws {
        stream = MockChatStreamService()
        session = MockCoachSessionClient()
        pendingClient = MockPendingActionsClient()
        pairing = MockPairingService()
        userId = "pending-actions-\(UUID().uuidString)"
        pairing.configurePaired(token: "test-token", userId: userId)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.coachSessionID(userID: userId))
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.coachSessionID(userID: userId))
    }

    private func makeViewModel(isMockCoachPath: Bool = false) -> CoachViewModel {
        CoachViewModel(dependencies: AppDependencies(
            apiService: MockAPIService(),
            pairingService: pairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: stream,
            coachSessionClient: session,
            pendingActionsClient: pendingClient,
            isMockCoachPath: isMockCoachPath
        ))
    }

    func testMediumRiskActionShowsConfirmationBeforeAnyExecution() async {
        let viewModel = makeViewModel()
        stream.eventsToYield = [
            .messageStart(sessionId: "s-pending", traceId: nil),
            .contentDelta(text: "Yes - approve before I touch your watch."),
            .functionResult(toolUseId: "tool-1", name: "coach_execute", result: pendingActionCreatedJSON(actionId: "pa_ios_1")),
            .messageEnd(sessionId: "s-pending", tokensUsed: 8, latencyMs: 80)
        ]

        await viewModel.sendMessage("Shuffle Thursday?")

        XCTAssertEqual(viewModel.pendingActionLifecycle.count, 1)
        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.riskTier, .medium)
        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.executionStatus, .pending)
        XCTAssertEqual(viewModel.messages.last?.pendingActions.count, 1)
        XCTAssertTrue(pendingClient.confirmationRequests.isEmpty, "streaming a PendingAction must not execute it")
    }

    func testApproveAndRejectUseSharedExecutePathAndUpdateState() async {
        let approveVM = makeViewModel()
        let approve = pendingAction(actionId: "pa_approve")
        approveVM.messages = [ChatMessage(role: .assistant, content: "Approve?", pendingActions: [approve])]
        approveVM.pendingActionLifecycle = [approve]

        pendingClient.responses = [
            PendingActionExecuteResponse(
                status: "succeeded",
                mode: "mock",
                action: updated(approve, status: .succeeded, responseStatus: "succeeded"),
                outcome: ["applied_action_id": .string(approve.actionId)],
                error: nil,
                sideEffectCount: 1,
                dependencyStatus: ["supabase": "mock", "redis_iris": "skip", "llm": "skip"]
            )
        ]
        await approveVM.confirmPendingAction(approve, decision: .approve)

        XCTAssertEqual(pendingClient.confirmationRequests.map(\.decision), [.approve])
        XCTAssertEqual(approveVM.pendingActionLifecycle.first?.executionStatus, .succeeded)

        let rejectVM = makeViewModel()
        let reject = pendingAction(actionId: "pa_reject")
        rejectVM.messages = [ChatMessage(role: .assistant, content: "Reject?", pendingActions: [reject])]
        rejectVM.pendingActionLifecycle = [reject]
        pendingClient.responses = [
            PendingActionExecuteResponse(
                status: "blocked",
                mode: "mock",
                action: updated(reject, status: .declined, responseStatus: "blocked"),
                outcome: ["decision": .string("reject")],
                error: nil,
                sideEffectCount: 0,
                dependencyStatus: ["supabase": "mock", "redis_iris": "skip", "llm": "skip"]
            )
        ]
        await rejectVM.confirmPendingAction(reject, decision: .reject)

        XCTAssertEqual(Array(pendingClient.confirmationRequests.map(\.decision).suffix(1)), [.reject])
        XCTAssertEqual(rejectVM.pendingActionLifecycle.first?.executionStatus, .declined)
    }

    func testDoubleApproveIsBusyGatedAndReplayResponseIsNoopState() async {
        let viewModel = makeViewModel()
        let action = pendingAction(actionId: "pa_replay")
        viewModel.messages = [ChatMessage(role: .assistant, content: "Approve?", pendingActions: [action])]
        viewModel.pendingActionLifecycle = [action]
        pendingClient.responses = [
            PendingActionExecuteResponse(
                status: "replayed_noop",
                mode: "mock",
                action: updated(action, status: .succeeded, responseStatus: "replayed_noop"),
                outcome: ["applied_action_id": .string(action.actionId)],
                error: nil,
                sideEffectCount: 1,
                dependencyStatus: ["supabase": "mock", "redis_iris": "skip", "llm": "skip"]
            )
        ]

        viewModel.pendingActionBusyIds.insert(action.actionId)
        await viewModel.confirmPendingAction(action, decision: .approve)
        XCTAssertTrue(pendingClient.confirmationRequests.isEmpty, "a second tap while confirm is in-flight must not hit execute")
        viewModel.pendingActionBusyIds.remove(action.actionId)
        await viewModel.confirmPendingAction(action, decision: .approve)
        XCTAssertEqual(pendingClient.confirmationRequests.count, 1)
        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.lastResponseStatus, "replayed_noop")
        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.executionStatus, .succeeded)
    }

    func testDeclinedExpiredStaleTerminalStatesDoNotDuplicateSideEffects() async {
        let viewModel = makeViewModel()
        let declined = updated(pendingAction(actionId: "pa_declined"), status: .declined, responseStatus: "blocked")
        let expired = updated(pendingAction(actionId: "pa_expired"), status: .expired, responseStatus: "replayed_noop")
        let stale = updated(pendingAction(actionId: "pa_stale"), status: .stale, responseStatus: "stale")
        let terminal = updated(pendingAction(actionId: "pa_terminal"), status: .failedTerminal, responseStatus: "replayed_noop")
        viewModel.pendingActionLifecycle = [declined, expired, stale, terminal]

        XCTAssertTrue(declined.executionStatus.isTerminal)
        XCTAssertTrue(expired.executionStatus.isTerminal)
        XCTAssertTrue(terminal.executionStatus.isTerminal)
        XCTAssertFalse(stale.executionStatus.acceptsConfirmationDecision)

        await viewModel.confirmPendingAction(declined, decision: .approve)
        await viewModel.confirmPendingAction(expired, decision: .approve)
        await viewModel.confirmPendingAction(stale, decision: .approve)
        await viewModel.confirmPendingAction(terminal, decision: .approve)

        XCTAssertTrue(pendingClient.confirmationRequests.isEmpty, "terminal or stale confirmations must not hit execute again")
    }

    func testDependencyDownDegradesToDataGapNotSilentSuccess() async {
        let viewModel = makeViewModel()
        let action = pendingAction(actionId: "pa_data_gap")
        let envelope = PendingActionErrorEnvelope(
            mode: "data_gap",
            code: "dependency_unavailable",
            message: "Execution dependency unavailable; returned data_gap envelope.",
            retryable: true,
            dataGaps: [["code": "pending_actions:dependency_unavailable", "source": "execute"]]
        )
        viewModel.messages = [ChatMessage(role: .assistant, content: "Approve?", pendingActions: [action])]
        viewModel.pendingActionLifecycle = [action]
        pendingClient.responses = [
            PendingActionExecuteResponse(
                status: "failed_retryable",
                mode: "data_gap",
                action: updated(action, status: .failedRetryable, responseStatus: "failed_retryable", error: envelope),
                outcome: nil,
                error: envelope,
                sideEffectCount: 0,
                dependencyStatus: ["supabase": "mock", "redis_iris": "skip", "llm": "skip"]
            )
        ]

        await viewModel.confirmPendingAction(action, decision: .approve)

        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.executionStatus, .failedRetryable)
        XCTAssertEqual(viewModel.pendingActionLifecycle.first?.error?.mode, "data_gap")
        XCTAssertEqual(viewModel.degradeMode, .dataGap)
    }

    private func pendingAction(actionId: String) -> PendingActionContract {
        PendingActionContract(
            actionId: actionId,
            toolName: "propose_schedule_workout",
            riskTier: .medium,
            executionStatus: .pending,
            title: "Move Thursday's threshold run to Saturday",
            why: "You flagged feeling flat and Thursday clashes with your late meeting. Saturday keeps the weekly load intact.",
            exactSteps: [
                "Swap Thu 4x8 threshold -> Sat, move long run to Sun",
                "Re-push both workouts to your Garmin watch",
                "Update this week's plan in the app"
            ],
            normalizedPayload: [
                "target": .string("session:intervals-42"),
                "workout_id": .string("wrk_intervals_42")
            ]
        )
    }

    private func updated(
        _ action: PendingActionContract,
        status: PendingActionExecutionStatus,
        responseStatus: String,
        error: PendingActionErrorEnvelope? = nil
    ) -> PendingActionContract {
        var copy = action
        copy.executionStatus = status
        copy.lastResponseStatus = responseStatus
        copy.error = error
        return copy
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
            "idempotency_key": "pending-action:v1:test"
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
