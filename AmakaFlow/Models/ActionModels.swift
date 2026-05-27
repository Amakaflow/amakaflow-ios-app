//
//  ActionModels.swift
//  AmakaFlow
//
//  Generic agent action envelope for the Agent Inbox (AMA-1956 / AMA-1934).
//

import Foundation

// MARK: - Agent Actions

struct AgentAction: Codable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let rationale: String?
    let status: AgentActionStatus
    let decisionRequired: Bool
    let reversible: Bool
    let riskLevel: AgentActionRiskLevel?
    let preview: String?
    let expiresAt: String?
    let createdAt: String
    let appliedAt: String?
    let payload: [String: AnyCodable]?

    init(
        id: String,
        kind: String,
        title: String,
        rationale: String? = nil,
        status: AgentActionStatus,
        decisionRequired: Bool,
        reversible: Bool,
        riskLevel: AgentActionRiskLevel? = nil,
        preview: String? = nil,
        expiresAt: String? = nil,
        createdAt: String,
        appliedAt: String? = nil,
        payload: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.status = status
        self.decisionRequired = decisionRequired
        self.reversible = reversible
        self.riskLevel = riskLevel
        self.preview = preview
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.appliedAt = appliedAt
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case rationale
        case status
        case decisionRequired
        case reversible
        case riskLevel
        case preview
        case expiresAt
        case createdAt
        case appliedAt
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = (try? container.decode(String.self, forKey: .kind)) ?? "unknown"
        title = (try? container.decode(String.self, forKey: .title)) ?? Self.humanizedKind(kind)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        status = (try? container.decode(AgentActionStatus.self, forKey: .status)) ?? .unknown
        decisionRequired = (try? container.decode(Bool.self, forKey: .decisionRequired)) ?? (status == .pending)
        reversible = (try? container.decode(Bool.self, forKey: .reversible)) ?? false
        riskLevel = try container.decodeIfPresent(AgentActionRiskLevel.self, forKey: .riskLevel)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        createdAt = (try? container.decode(String.self, forKey: .createdAt)) ?? ""
        appliedAt = try container.decodeIfPresent(String.self, forKey: .appliedAt)
        payload = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .payload)
    }

    private static func humanizedKind(_ kind: String) -> String {
        kind
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

enum AgentActionStatus: Codable, Equatable {
    case pending
    case applied
    case rejected
    case undone
    case unknown

    var rawValue: String {
        switch self {
        case .pending: return "pending"
        case .applied: return "applied"
        case .rejected: return "rejected"
        case .undone: return "undone"
        case .unknown: return "unknown"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self))?.lowercased()
        switch value {
        case "pending": self = .pending
        case "applied", "approved": self = .applied
        case "rejected": self = .rejected
        case "undone": self = .undone
        default: self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum AgentActionRiskLevel: Codable, Equatable {
    case low
    case medium
    case high
    case unknown

    var rawValue: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        case .unknown: return "unknown"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self))?.lowercased()
        switch value {
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        default: self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension AgentAction {
    static let samplePending = AgentAction(
        id: "agent-action-pending",
        kind: "session_moved",
        title: "Review schedule change",
        rationale: "Coach recommends moving today’s harder work to protect recovery.",
        status: .pending,
        decisionRequired: true,
        reversible: true,
        riskLevel: .medium,
        preview: "Today → Tomorrow",
        expiresAt: nil,
        createdAt: "2026-05-26T12:00:00Z",
        appliedAt: nil,
        payload: nil
    )

    static let sampleApplied = AgentAction(
        id: "agent-action-applied",
        kind: "rest_day",
        title: "Rest day applied",
        rationale: "Coach swapped intensity for recovery after a fatigue spike.",
        status: .applied,
        decisionRequired: false,
        reversible: true,
        riskLevel: .low,
        preview: "Intervals → Mobility + walk",
        expiresAt: nil,
        createdAt: "2026-05-26T12:00:00Z",
        appliedAt: "2026-05-26T12:01:00Z",
        payload: nil
    )
}
