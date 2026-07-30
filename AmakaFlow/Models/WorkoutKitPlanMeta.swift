//
//  WorkoutKitPlanMeta.swift
//  AmakaFlow
//
//  AMA-2351 — composition / routing_reason for preview (mapper WKPlanDTO).
//

import Foundation

/// Lightweight decode of mapper composition fields without depending on a
/// workoutkit-sync version that exposes them on `WKPlanDTO`.
struct WorkoutKitPlanMeta: Equatable, Sendable {
    let composition: String
    let compositionEffective: String
    let routingReason: String

    static let fallback = WorkoutKitPlanMeta(
        composition: "custom",
        compositionEffective: "custom",
        routingReason: "legacy_unspecified"
    )

    init(composition: String, compositionEffective: String, routingReason: String) {
        self.composition = composition
        self.compositionEffective = compositionEffective
        self.routingReason = routingReason
    }

    init(fromMapperJSON data: Data) {
        struct Payload: Decodable {
            let composition: String?
            let compositionEffective: String?
            let composition_effective: String?
            let routingReason: String?
            let routing_reason: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            self = .fallback
            return
        }
        let composition = payload.composition ?? "custom"
        let effective = payload.compositionEffective
            ?? payload.composition_effective
            ?? composition
        let reason = payload.routingReason
            ?? payload.routing_reason
            ?? "legacy_unspecified"
        self.init(
            composition: composition,
            compositionEffective: effective,
            routingReason: reason
        )
    }
}

enum WorkoutKitRoutingCopy {
    /// Humanized preview line for Start sheet / post-schedule status.
    static func compositionLine(meta: WorkoutKitPlanMeta) -> String {
        let reason = humanizedReason(meta.routingReason)
        return "Apple Workout · \(meta.compositionEffective) · \(reason)"
    }

    static func humanizedReason(_ code: String) -> String {
        switch code {
        case "multisport_ordered_legs":
            return "multisport legs"
        case "pool_swim_structured":
            return "structured pool swim"
        case "structured_intervals":
            return "interval structure"
        case "strength_sets":
            return "strength sets"
        case "distance_and_time":
            return "pace target"
        case "distance_only", "single_distance":
            return "distance goal"
        case "time_only", "single_time":
            return "time goal"
        case "open_goal", "fallback_custom", "legacy_unspecified":
            return "custom plan"
        default:
            return code.replacingOccurrences(of: "_", with: " ")
        }
    }
}
