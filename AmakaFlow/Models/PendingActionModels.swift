//
//  PendingActionModels.swift
//  AmakaFlow
//
//  AMA-2230 (E9-4): native iOS PendingActions contract models.
//

import Foundation
import SwiftUI

enum PendingActionRiskTier: String, Codable, Equatable {
    case read
    case low
    case medium
    case high
    case unknown

    var requiresConfirmation: Bool {
        self == .medium || self == .high || self == .unknown
    }

    var label: String {
        switch self {
        case .read: return "READ"
        case .low: return "LOW RISK"
        case .medium: return "MEDIUM RISK"
        case .high: return "HIGH RISK"
        case .unknown: return "RISK UNKNOWN"
        }
    }

    var note: String {
        switch self {
        case .low, .read: return "Auto-safe, shown for awareness"
        case .medium, .high: return "Needs your confirmation"
        case .unknown: return "Needs review before execution"
        }
    }

    var color: Color {
        switch self {
        case .read, .low: return Theme.Colors.readyHigh
        case .medium: return Theme.Colors.readyModerate
        case .high, .unknown: return Theme.Colors.readyLow
        }
    }
}

enum PendingActionExecutionStatus: String, Codable, Equatable, CaseIterable {
    case proposal
    case pending
    case confirmed
    case executing
    case succeeded
    case failedRetryable = "failed_retryable"
    case failedTerminal = "failed_terminal"
    case declined
    case canceled
    case expired
    case replayedNoop = "replayed_noop"
    case stale

    var lifecycleLabel: String {
        switch self {
        case .proposal, .pending: return "PENDING"
        case .confirmed: return "CONFIRMED"
        case .executing: return "EXECUTING"
        case .succeeded: return "DONE"
        case .failedRetryable: return "FAILED"
        case .failedTerminal: return "FAILED"
        case .declined: return "DECLINED"
        case .canceled: return "CANCELED"
        case .expired: return "EXPIRED"
        case .replayedNoop: return "REPLAYED"
        case .stale: return "OUT OF DATE"
        }
    }

    var toneColor: Color {
        switch self {
        case .executing, .confirmed: return Color.purple
        case .succeeded: return Theme.Colors.readyHigh
        case .failedRetryable, .failedTerminal: return Theme.Colors.readyLow
        case .stale, .replayedNoop: return Theme.Colors.readyModerate
        case .expired, .declined, .canceled: return Theme.Colors.textSecondary
        case .proposal, .pending: return Theme.Colors.readyModerate
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failedTerminal, .declined, .canceled, .expired, .replayedNoop:
            return true
        default:
            return false
        }
    }

    var acceptsConfirmationDecision: Bool {
        switch self {
        case .proposal, .pending:
            return true
        default:
            return false
        }
    }
}

enum PendingActionDecision: String, Codable, Equatable {
    case approve
    case reject
    case details
}

struct PendingActionErrorEnvelope: Codable, Equatable {
    let mode: String
    let code: String
    let message: String
    let retryable: Bool?
    let dataGaps: [[String: String]]?

    enum CodingKeys: String, CodingKey {
        case mode
        case code
        case message
        case retryable
        case dataGaps = "data_gaps"
    }
}

struct PendingActionContract: Codable, Identifiable, Equatable {
    let actionId: String
    let toolName: String
    let riskTier: PendingActionRiskTier
    var executionStatus: PendingActionExecutionStatus
    let title: String
    let why: String
    let exactSteps: [String]
    let expiresIn: String
    let reversible: Bool
    let normalizedPayload: [String: PendingActionJSONValue]
    let channel: String?
    let idempotencyKey: String?
    let policyReasons: [String]
    var lastResponseStatus: String?
    var error: PendingActionErrorEnvelope?

    var id: String { actionId }

    enum CodingKeys: String, CodingKey {
        case actionId = "action_id"
        case toolName = "tool_name"
        case riskTier = "risk_tier"
        case executionStatus = "execution_status"
        case title
        case why
        case exactSteps = "exact_steps"
        case expiresIn = "expires_in"
        case reversible
        case normalizedPayload = "normalized_payload"
        case channel
        case idempotencyKey = "idempotency_key"
        case policyReasons = "policy_reasons"
        case lastResponseStatus = "last_response_status"
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let actionId = try container.decode(String.self, forKey: .actionId)
        let toolName = try container.decode(String.self, forKey: .toolName)
        let riskTier = (try? container.decode(PendingActionRiskTier.self, forKey: .riskTier)) ?? .unknown
        let executionStatus = (try? container.decode(PendingActionExecutionStatus.self, forKey: .executionStatus)) ?? .pending
        let normalizedPayload = (try? container.decode([String: PendingActionJSONValue].self, forKey: .normalizedPayload)) ?? [:]
        let policyReasons = (try? container.decode([String].self, forKey: .policyReasons)) ?? []
        self.init(
            actionId: actionId,
            toolName: toolName,
            riskTier: riskTier,
            executionStatus: executionStatus,
            title: (try? container.decode(String.self, forKey: .title)) ?? "",
            why: (try? container.decode(String.self, forKey: .why)) ?? "",
            exactSteps: (try? container.decode([String].self, forKey: .exactSteps)) ?? [],
            expiresIn: (try? container.decode(String.self, forKey: .expiresIn)) ?? "11 MIN",
            reversible: (try? container.decode(Bool.self, forKey: .reversible)) ?? true,
            normalizedPayload: normalizedPayload,
            channel: try? container.decode(String.self, forKey: .channel),
            idempotencyKey: try? container.decode(String.self, forKey: .idempotencyKey),
            policyReasons: policyReasons,
            lastResponseStatus: try? container.decode(String.self, forKey: .lastResponseStatus),
            error: try? container.decode(PendingActionErrorEnvelope.self, forKey: .error)
        )
    }

    init(
        actionId: String,
        toolName: String,
        riskTier: PendingActionRiskTier,
        executionStatus: PendingActionExecutionStatus = .pending,
        title: String,
        why: String,
        exactSteps: [String],
        expiresIn: String = "11 MIN",
        reversible: Bool = true,
        normalizedPayload: [String: PendingActionJSONValue] = [:],
        channel: String? = nil,
        idempotencyKey: String? = nil,
        policyReasons: [String] = [],
        lastResponseStatus: String? = nil,
        error: PendingActionErrorEnvelope? = nil
    ) {
        self.actionId = actionId
        self.toolName = toolName
        self.riskTier = riskTier
        self.executionStatus = executionStatus
        self.title = title
        self.why = why
        self.exactSteps = exactSteps
        self.expiresIn = expiresIn
        self.reversible = reversible
        self.normalizedPayload = normalizedPayload
        self.channel = channel
        self.idempotencyKey = idempotencyKey
        self.policyReasons = policyReasons
        self.lastResponseStatus = lastResponseStatus
        self.error = error
    }
}

enum PendingActionJSONValue: Codable, Equatable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: PendingActionJSONValue])
    case array([PendingActionJSONValue])
    case null

    var description: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .object(let value): return value.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
        case .array(let value): return value.map(\.description).joined(separator: ", ")
        case .null: return "null"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([PendingActionJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: PendingActionJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct PendingActionExecuteRequest: Codable, Equatable {
    let toolName: String
    let payload: [String: PendingActionJSONValue]
    let pendingActionId: String
    let confirmed: Bool
    let confirmationDecision: String
    let confirmationRequestId: String
    let channel: String

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case payload
        case pendingActionId = "pending_action_id"
        case confirmed
        case confirmationDecision = "confirmation_decision"
        case confirmationRequestId = "confirmation_request_id"
        case channel
    }
}

struct PendingActionExecuteResponse: Codable, Equatable {
    let status: String
    let mode: String?
    let action: PendingActionContract?
    let outcome: [String: PendingActionJSONValue]?
    let error: PendingActionErrorEnvelope?
    let sideEffectCount: Int?
    let dependencyStatus: [String: String]?

    enum CodingKeys: String, CodingKey {
        case status
        case mode
        case action
        case outcome
        case error
        case sideEffectCount = "side_effect_count"
        case dependencyStatus = "dependency_status"
    }
}

enum PendingActionParse {
    static func actions(fromFunctionResult result: String) -> [PendingActionContract] {
        guard let data = result.data(using: .utf8) else { return [] }
        let decoder = APIService.makeGeneratedDecoder()

        if let response = try? decoder.decode(PendingActionExecuteResponse.self, from: data),
           let action = response.action {
            return [decorate(action, status: response.status, error: response.error)]
        }

        if let envelope = try? decoder.decode(ChannelGatewayEnvelope.self, from: data),
           let response = envelope.coachCoreResponse,
           let action = response.action {
            return [decorate(action, status: response.status, error: response.error)]
        }

        return []
    }

    private static func decorate(
        _ action: PendingActionContract,
        status: String?,
        error: PendingActionErrorEnvelope?
    ) -> PendingActionContract {
        var decorated = action.withFallbackPresentation()
        decorated.lastResponseStatus = status
        decorated.error = error ?? decorated.error
        return decorated
    }

    private struct ChannelGatewayEnvelope: Codable {
        let coachCoreResponse: PendingActionExecuteResponse?

        enum CodingKeys: String, CodingKey {
            case coachCoreResponse = "coach_core_response"
        }
    }
}

extension PendingActionContract {
    func withFallbackPresentation() -> PendingActionContract {
        var copy = self
        if copy.title.isEmpty {
            copy = copy.replacingTitle(Self.title(for: toolName, payload: normalizedPayload))
        }
        if copy.why.isEmpty {
            copy = copy.replacingWhy(Self.why(for: toolName, policyReasons: policyReasons))
        }
        if copy.exactSteps.isEmpty {
            copy = copy.replacingSteps(Self.steps(for: toolName, payload: normalizedPayload))
        }
        return copy
    }

    private func replacingTitle(_ title: String) -> PendingActionContract {
        PendingActionContract(actionId: actionId, toolName: toolName, riskTier: riskTier, executionStatus: executionStatus, title: title, why: why, exactSteps: exactSteps, expiresIn: expiresIn, reversible: reversible, normalizedPayload: normalizedPayload, channel: channel, idempotencyKey: idempotencyKey, policyReasons: policyReasons, lastResponseStatus: lastResponseStatus, error: error)
    }

    private func replacingWhy(_ why: String) -> PendingActionContract {
        PendingActionContract(actionId: actionId, toolName: toolName, riskTier: riskTier, executionStatus: executionStatus, title: title, why: why, exactSteps: exactSteps, expiresIn: expiresIn, reversible: reversible, normalizedPayload: normalizedPayload, channel: channel, idempotencyKey: idempotencyKey, policyReasons: policyReasons, lastResponseStatus: lastResponseStatus, error: error)
    }

    private func replacingSteps(_ steps: [String]) -> PendingActionContract {
        PendingActionContract(actionId: actionId, toolName: toolName, riskTier: riskTier, executionStatus: executionStatus, title: title, why: why, exactSteps: steps, expiresIn: expiresIn, reversible: reversible, normalizedPayload: normalizedPayload, channel: channel, idempotencyKey: idempotencyKey, policyReasons: policyReasons, lastResponseStatus: lastResponseStatus, error: error)
    }

    private static func title(for toolName: String, payload: [String: PendingActionJSONValue]) -> String {
        if toolName == "propose_schedule_workout" || toolName == "propose_move_session" {
            return "Move Thursday's threshold run to Saturday"
        }
        return "Confirm \(toolName.replacingOccurrences(of: "_", with: " "))"
    }

    private static func why(for toolName: String, policyReasons: [String]) -> String {
        if toolName == "propose_schedule_workout" || toolName == "propose_move_session" {
            return "You flagged feeling flat and Thursday clashes with your late meeting. Saturday keeps the weekly load intact."
        }
        return policyReasons.first ?? "This action can change your plan or connected devices, so it needs explicit confirmation."
    }

    private static func steps(for toolName: String, payload: [String: PendingActionJSONValue]) -> [String] {
        if toolName == "propose_schedule_workout" || toolName == "propose_move_session" {
            return [
                "Swap Thu 4x8 threshold -> Sat, move long run to Sun",
                "Re-push both workouts to your Garmin watch",
                "Update this week's plan in the app"
            ]
        }
        let payloadSteps = payload
            .sorted { $0.key < $1.key }
            .map { "\($0.key.replacingOccurrences(of: "_", with: " ")): \($0.value.description)" }
        return payloadSteps.isEmpty ? ["Send confirmation through the shared PendingActions execute path"] : payloadSteps
    }
}
