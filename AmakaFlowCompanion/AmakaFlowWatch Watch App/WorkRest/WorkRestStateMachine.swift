//
//  WorkRestStateMachine.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 Phase 4 — confidence-gated IDLE/REST ↔ WORK SET engine (pure / testable).
//  Heart rate is supporting context only — never used for rep counting or sole trigger.
//

import Foundation

struct WorkRestObservation: Equatable {
    /// 0…1 activity estimate from IMU (see `WorkRestMotionMetrics.activityScore`).
    let activityScore: Double
    let sampleCount: Int
    /// Optional live HR (bpm). Effort/rest context only.
    let heartRateBPM: Double?
    let now: Date

    init(
        activityScore: Double,
        sampleCount: Int,
        heartRateBPM: Double? = nil,
        now: Date = Date()
    ) {
        self.activityScore = activityScore
        self.sampleCount = sampleCount
        self.heartRateBPM = heartRateBPM
        self.now = now
    }
}

struct WorkRestEvaluateResult: Equatable {
    let phase: WorkRestPhase
    let inferredPhase: WorkRestPhase
    let confidence: Double
    let motionConfidence: Double
    /// Non-nil only when confidence clears the prompt gate and cooldown allows.
    let proposal: WorkRestProposal?
}

/// Pure state machine — no CoreMotion / WatchKit. Safe for unit tests + simulator.
struct WorkRestStateMachine {
    enum Defaults {
        static let promptConfidenceThreshold: Double = 0.72
        /// Motion must be within this margin of the threshold before HR can help clear it.
        static let motionFloorBeforeHRAssist: Double = 0.67
        static let workActivityThreshold: Double = 0.42
        static let restActivityThreshold: Double = 0.22
        static let minSamples: Int = 25
        static let rejectCooldownSeconds: TimeInterval = 20
        static let proposalHoldSeconds: TimeInterval = 12
        static let elevatedHeartRateBPM: Double = 110
        static let recoveredHeartRateBPM: Double = 95
        static let maxHeartRateConfidenceBoost: Double = 0.08
    }

    private(set) var phase: WorkRestPhase
    private(set) var pendingProposal: WorkRestProposal?
    private var lastRejectAt: Date?
    private var lastRejectedTransition: WorkRestTransition?
    private var proposalPresentedAt: Date?

    var promptConfidenceThreshold: Double
    var workActivityThreshold: Double
    var restActivityThreshold: Double
    var minSamples: Int
    var rejectCooldownSeconds: TimeInterval
    var proposalHoldSeconds: TimeInterval
    var elevatedHeartRateBPM: Double
    var recoveredHeartRateBPM: Double

    init(
        phase: WorkRestPhase = .idleRest,
        promptConfidenceThreshold: Double = Defaults.promptConfidenceThreshold,
        workActivityThreshold: Double = Defaults.workActivityThreshold,
        restActivityThreshold: Double = Defaults.restActivityThreshold,
        minSamples: Int = Defaults.minSamples,
        rejectCooldownSeconds: TimeInterval = Defaults.rejectCooldownSeconds,
        proposalHoldSeconds: TimeInterval = Defaults.proposalHoldSeconds,
        elevatedHeartRateBPM: Double = Defaults.elevatedHeartRateBPM,
        recoveredHeartRateBPM: Double = Defaults.recoveredHeartRateBPM
    ) {
        self.phase = phase
        self.promptConfidenceThreshold = promptConfidenceThreshold
        self.workActivityThreshold = workActivityThreshold
        self.restActivityThreshold = restActivityThreshold
        self.minSamples = minSamples
        self.rejectCooldownSeconds = rejectCooldownSeconds
        self.proposalHoldSeconds = proposalHoldSeconds
        self.elevatedHeartRateBPM = elevatedHeartRateBPM
        self.recoveredHeartRateBPM = recoveredHeartRateBPM
    }

    mutating func syncPhase(_ newPhase: WorkRestPhase) {
        guard phase != newPhase else { return }
        phase = newPhase
        clearProposal()
    }

    /// Evaluate a motion (+ optional HR) observation. Never mutates phase without confirm/reject.
    mutating func evaluate(_ observation: WorkRestObservation) -> WorkRestEvaluateResult {
        guard observation.sampleCount >= minSamples else {
            return WorkRestEvaluateResult(
                phase: phase,
                inferredPhase: phase,
                confidence: 0,
                motionConfidence: 0,
                proposal: pendingProposal
            )
        }

        let inferred = inferPhase(activityScore: observation.activityScore)
        let motionConfidence = motionConfidence(
            activityScore: observation.activityScore,
            inferred: inferred
        )
        let (confidence, usedHR) = applyHeartRateContext(
            motionConfidence: motionConfidence,
            inferred: inferred,
            heartRateBPM: observation.heartRateBPM
        )

        if let pending = pendingProposal {
            // Keep showing until user acts or hold expires.
            if let presented = proposalPresentedAt,
               observation.now.timeIntervalSince(presented) < proposalHoldSeconds {
                return WorkRestEvaluateResult(
                    phase: phase,
                    inferredPhase: inferred,
                    confidence: confidence,
                    motionConfidence: motionConfidence,
                    proposal: pending
                )
            }
            // Unanswered prompt expired — quiet interval before re-proposing same transition.
            lastRejectedTransition = pending.transition
            lastRejectAt = observation.now
            clearProposal()
            return WorkRestEvaluateResult(
                phase: phase,
                inferredPhase: inferred,
                confidence: confidence,
                motionConfidence: motionConfidence,
                proposal: nil
            )
        }

        guard inferred != phase else {
            return WorkRestEvaluateResult(
                phase: phase,
                inferredPhase: inferred,
                confidence: confidence,
                motionConfidence: motionConfidence,
                proposal: nil
            )
        }

        let transition: WorkRestTransition = inferred == .workSet ? .toWorkSet : .toIdleRest

        // Low confidence → stay manual (no prompt).
        // HR may nudge but cannot invent a prompt from weak motion alone.
        let motionClearsFloor = motionConfidence >= Defaults.motionFloorBeforeHRAssist
        let clearsPromptGate = confidence >= promptConfidenceThreshold && motionClearsFloor

        guard clearsPromptGate else {
            return WorkRestEvaluateResult(
                phase: phase,
                inferredPhase: inferred,
                confidence: confidence,
                motionConfidence: motionConfidence,
                proposal: nil
            )
        }

        if isInRejectCooldown(transition: transition, now: observation.now) {
            return WorkRestEvaluateResult(
                phase: phase,
                inferredPhase: inferred,
                confidence: confidence,
                motionConfidence: motionConfidence,
                proposal: nil
            )
        }

        let proposal = WorkRestProposal(
            transition: transition,
            confidence: confidence,
            motionConfidence: motionConfidence,
            usedHeartRateContext: usedHR
        )
        pendingProposal = proposal
        proposalPresentedAt = observation.now

        return WorkRestEvaluateResult(
            phase: phase,
            inferredPhase: inferred,
            confidence: confidence,
            motionConfidence: motionConfidence,
            proposal: proposal
        )
    }

    /// User accepted the proposal — apply transition.
    @discardableResult
    mutating func confirmPendingProposal() -> WorkRestTransition? {
        guard let pending = pendingProposal else { return nil }
        phase = pending.transition.targetPhase
        clearProposal()
        lastRejectAt = nil
        lastRejectedTransition = nil
        return pending.transition
    }

    /// User rejected — stay manual; cooldown before re-prompting same transition.
    mutating func rejectPendingProposal(now: Date = Date()) {
        if let pending = pendingProposal {
            lastRejectedTransition = pending.transition
            lastRejectAt = now
        }
        clearProposal()
    }

    mutating func clearProposal() {
        pendingProposal = nil
        proposalPresentedAt = nil
    }

    // MARK: - Private

    private func inferPhase(activityScore: Double) -> WorkRestPhase {
        switch phase {
        case .idleRest:
            return activityScore >= workActivityThreshold ? .workSet : .idleRest
        case .workSet:
            return activityScore <= restActivityThreshold ? .idleRest : .workSet
        }
    }

    private func motionConfidence(activityScore: Double, inferred: WorkRestPhase) -> Double {
        switch inferred {
        case .workSet:
            let span = max(0.001, 1.0 - workActivityThreshold)
            let raw = (activityScore - workActivityThreshold) / span
            return clamp01(0.55 + raw * 0.45)
        case .idleRest:
            let span = max(0.001, restActivityThreshold)
            let raw = (restActivityThreshold - activityScore) / span
            return clamp01(0.55 + raw * 0.45)
        }
    }

    /// HR is effort/rest context only — small boost, never sole trigger.
    private func applyHeartRateContext(
        motionConfidence: Double,
        inferred: WorkRestPhase,
        heartRateBPM: Double?
    ) -> (confidence: Double, usedHR: Bool) {
        guard let heartRate = heartRateBPM, heartRate > 0 else {
            return (motionConfidence, false)
        }

        var boost = 0.0
        switch inferred {
        case .workSet where heartRate >= elevatedHeartRateBPM:
            boost = Defaults.maxHeartRateConfidenceBoost
        case .idleRest where heartRate > 0 && heartRate <= recoveredHeartRateBPM:
            boost = Defaults.maxHeartRateConfidenceBoost * 0.75
        default:
            break
        }

        guard boost > 0 else { return (motionConfidence, false) }
        return (clamp01(motionConfidence + boost), true)
    }

    private func isInRejectCooldown(transition: WorkRestTransition, now: Date) -> Bool {
        guard let rejected = lastRejectedTransition,
              rejected == transition,
              let rejectedAt = lastRejectAt else { return false }
        return now.timeIntervalSince(rejectedAt) < rejectCooldownSeconds
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
