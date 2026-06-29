//
//  PendingActionsClient.swift
//  AmakaFlow
//
//  Thin iOS adapter over the shared Epic 8 PendingActions execute route.
//

import Foundation

protocol PendingActionsProviding {
    func confirm(
        action: PendingActionContract,
        decision: PendingActionDecision,
        token: String
    ) async throws -> PendingActionExecuteResponse
}

enum PendingActionsClientError: LocalizedError, Equatable {
    case invalidURL
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "PendingActions execute URL is invalid."
        case .httpError(let statusCode, _):
            return "PendingActions execute failed (\(statusCode))."
        }
    }
}

final class PendingActionsClient: PendingActionsProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func confirm(
        action: PendingActionContract,
        decision: PendingActionDecision,
        token: String
    ) async throws -> PendingActionExecuteResponse {
        let bffURL = "\(AppEnvironment.current.mobileBFFURL)/v1"
        guard let url = URL(string: "\(bffURL)/coach/execute") else {
            throw PendingActionsClientError.invalidURL
        }

        let requestBody = PendingActionExecuteRequest(
            toolName: action.toolName,
            payload: action.normalizedPayload,
            pendingActionId: action.actionId,
            confirmed: true,
            confirmationDecision: decision == .approve ? "approve" : "reject",
            confirmationRequestId: "ios:\(decision.rawValue):\(action.actionId)",
            channel: "app"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PendingActionsClientError.httpError(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        return try APIService.makeGeneratedDecoder().decode(PendingActionExecuteResponse.self, from: data)
    }
}

final class MockPendingActionsClient: PendingActionsProviding {
    var responses: [PendingActionExecuteResponse] = []
    var errorToThrow: Error?
    private(set) var confirmationRequests: [(action: PendingActionContract, decision: PendingActionDecision)] = []

    func confirm(
        action: PendingActionContract,
        decision: PendingActionDecision,
        token: String
    ) async throws -> PendingActionExecuteResponse {
        confirmationRequests.append((action, decision))
        if let errorToThrow {
            throw errorToThrow
        }
        if !responses.isEmpty {
            return responses.removeFirst()
        }
        var updated = action
        updated.executionStatus = decision == .approve ? .succeeded : .declined
        updated.lastResponseStatus = decision == .approve ? "succeeded" : "declined"
        return PendingActionExecuteResponse(
            status: updated.lastResponseStatus ?? "succeeded",
            mode: "mock",
            action: updated,
            outcome: ["applied_action_id": .string(updated.actionId)],
            error: nil,
            sideEffectCount: decision == .approve ? 1 : 0,
            dependencyStatus: [
                "supabase": "mock",
                "redis_iris": "skip",
                "llm": "skip"
            ]
        )
    }
}

final class PendingActionsFixtureChatStreamService: ChatStreamProviding {
    func stream(request: ChatStreamRequest, token: String) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.messageStart(sessionId: request.sessionId ?? "fixture-pending-actions", traceId: "fixture-ama-2230"))
                continuation.yield(.contentDelta(text: "Yes - here's what I'd change. Approve before I touch your watch."))
                continuation.yield(.functionResult(
                    toolUseId: "fixture-ama-2230",
                    name: "coach_execute",
                    result: Self.pendingActionCreatedJSON
                ))
                continuation.yield(.messageEnd(sessionId: request.sessionId ?? "fixture-pending-actions", tokensUsed: 12, latencyMs: 90))
                continuation.finish()
            }
        }
    }

    private static let pendingActionCreatedJSON = """
    {
      "status": "pending_action_created",
      "mode": "mock",
      "action": {
        "action_id": "pa_ios_ama_2230_fixture",
        "tool_name": "propose_schedule_workout",
        "risk_tier": "medium",
        "execution_status": "pending",
        "channel": "app",
        "normalized_payload": {
          "target": "session:threshold-thu",
          "workout_id": "wrk_threshold_42",
          "date": "2026-06-28",
          "reason": "Thursday conflicts with a late meeting"
        },
        "idempotency_key": "pending-action:v1:ama-2230-fixture"
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
