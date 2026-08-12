//
//  WorkRestPhase.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 Phase 4 — work / rest boundary assist phases.
//

import Foundation

/// IMU-facing boundary phases for strength auto-capture assist.
/// Distinct from `WorkoutPhase` (engine UI/timer); this never silently invents sets.
enum WorkRestPhase: String, Equatable, Codable, CaseIterable {
    /// Idle between sets / resting.
    case idleRest
    /// Actively working a set.
    case workSet
}

enum WorkRestTransition: String, Equatable, Codable {
    case toWorkSet
    case toIdleRest

    var targetPhase: WorkRestPhase {
        switch self {
        case .toWorkSet: return .workSet
        case .toIdleRest: return .idleRest
        }
    }

    var promptTitle: String {
        switch self {
        case .toWorkSet: return "Start work?"
        case .toIdleRest: return "Start rest?"
        }
    }

    var promptDetail: String {
        switch self {
        case .toWorkSet: return "Motion looks like a set — confirm to resume."
        case .toIdleRest: return "Motion looks quiet — confirm to rest."
        }
    }
}

/// Confidence-gated proposal. Never applied without explicit user confirm.
struct WorkRestProposal: Equatable {
    let transition: WorkRestTransition
    let confidence: Double
    let motionConfidence: Double
    let usedHeartRateContext: Bool

    var isHighConfidence: Bool {
        confidence >= WorkRestStateMachine.Defaults.promptConfidenceThreshold
    }
}
