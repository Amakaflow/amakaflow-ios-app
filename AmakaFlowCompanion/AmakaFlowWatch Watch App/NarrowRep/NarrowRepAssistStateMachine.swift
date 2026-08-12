//
//  NarrowRepAssistStateMachine.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 Phase 5 — ranked rep-count proposals (pure / testable).
//  Never mutates logged reps without explicit confirm.
//

import Foundation

struct NarrowRepObservation: Equatable {
    let family: NarrowRepExerciseFamily?
    let plannedReps: Int?
    let detectedRepCount: Int
    let sampleCount: Int
    /// True while athlete is in a work set (or just finished — finalizePass).
    let isWorkContext: Bool
    /// When true, allow proposing even if count just stabilized (e.g. entered rest).
    let finalizePass: Bool
    let now: Date

    init(
        family: NarrowRepExerciseFamily?,
        plannedReps: Int?,
        detectedRepCount: Int,
        sampleCount: Int,
        isWorkContext: Bool,
        finalizePass: Bool = false,
        now: Date = Date()
    ) {
        self.family = family
        self.plannedReps = plannedReps
        self.detectedRepCount = detectedRepCount
        self.sampleCount = sampleCount
        self.isWorkContext = isWorkContext
        self.finalizePass = finalizePass
        self.now = now
    }
}

struct NarrowRepCandidate: Equatable {
    let reps: Int
    let score: Double
    let source: Source

    enum Source: String, Equatable {
        case detected
        case planned
        case neighbor
    }
}

struct NarrowRepProposal: Equatable {
    let suggestedReps: Int
    let plannedReps: Int?
    let detectedRepCount: Int
    let confidence: Double
    let family: NarrowRepExerciseFamily
    let rankedCandidates: [NarrowRepCandidate]

    /// `autoConfirmed` when suggestion matches plan; otherwise `inferred`.
    var detectionMethod: String {
        if let planned = plannedReps, planned == suggestedReps {
            return "autoConfirmed"
        }
        return "inferred"
    }

    var promptTitle: String {
        "\(suggestedReps) reps?"
    }

    var promptDetail: String {
        if let planned = plannedReps, planned != suggestedReps {
            return "Detected \(detectedRepCount) · plan \(planned). Confirm to use."
        }
        if plannedReps == suggestedReps {
            return "Matches plan — confirm to apply."
        }
        return "From \(family.displayName.lowercased()) motion — confirm to apply."
    }
}

struct NarrowRepEvaluateResult: Equatable {
    let detectedRepCount: Int
    let topCandidate: NarrowRepCandidate?
    let confidence: Double
    let proposal: NarrowRepProposal?
}

/// Pure ranker — no CoreMotion / WatchKit.
struct NarrowRepAssistStateMachine {
    enum Defaults {
        static let promptConfidenceThreshold: Double = 0.72
        static let minSamples: Int = 40
        static let minDetectedReps: Int = 1
        static let maxDistanceFromPlan: Int = 4
        /// Same detected count must hold this many evaluates before mid-set prompt.
        static let stabilityPasses: Int = 2
        static let rejectCooldownSeconds: TimeInterval = 20
        static let proposalHoldSeconds: TimeInterval = 15
    }

    private(set) var pendingProposal: NarrowRepProposal?
    private var lastRejectAt: Date?
    private var lastRejectedReps: Int?
    private var proposalPresentedAt: Date?
    private var lastStableCount: Int?
    private var stablePassCount: Int = 0
    private var didConfirmThisSet = false

    var promptConfidenceThreshold: Double
    var minSamples: Int
    var rejectCooldownSeconds: TimeInterval
    var proposalHoldSeconds: TimeInterval
    var stabilityPasses: Int

    init(
        promptConfidenceThreshold: Double = Defaults.promptConfidenceThreshold,
        minSamples: Int = Defaults.minSamples,
        rejectCooldownSeconds: TimeInterval = Defaults.rejectCooldownSeconds,
        proposalHoldSeconds: TimeInterval = Defaults.proposalHoldSeconds,
        stabilityPasses: Int = Defaults.stabilityPasses
    ) {
        self.promptConfidenceThreshold = promptConfidenceThreshold
        self.minSamples = minSamples
        self.rejectCooldownSeconds = rejectCooldownSeconds
        self.proposalHoldSeconds = proposalHoldSeconds
        self.stabilityPasses = stabilityPasses
    }

    /// Call when a new set / work phase begins.
    mutating func beginSet() {
        clearProposal()
        lastStableCount = nil
        stablePassCount = 0
        didConfirmThisSet = false
        lastRejectedReps = nil
        lastRejectAt = nil
    }

    mutating func clearProposal() {
        pendingProposal = nil
        proposalPresentedAt = nil
    }

    mutating func confirmPendingProposal() -> NarrowRepProposal? {
        guard let pending = pendingProposal else { return nil }
        pendingProposal = nil
        proposalPresentedAt = nil
        didConfirmThisSet = true
        return pending
    }

    mutating func rejectPendingProposal(at now: Date = Date()) {
        if let pending = pendingProposal {
            lastRejectedReps = pending.suggestedReps
            lastRejectAt = now
        }
        clearProposal()
    }

    mutating func evaluate(_ observation: NarrowRepObservation) -> NarrowRepEvaluateResult {
        // Hold existing proposal until confirm / reject / hold expiry.
        if let pending = pendingProposal {
            if let presented = proposalPresentedAt,
               observation.now.timeIntervalSince(presented) >= proposalHoldSeconds {
                lastRejectedReps = pending.suggestedReps
                lastRejectAt = observation.now
                clearProposal()
            } else {
                return NarrowRepEvaluateResult(
                    detectedRepCount: observation.detectedRepCount,
                    topCandidate: pending.rankedCandidates.first,
                    confidence: pending.confidence,
                    proposal: pending
                )
            }
        }

        guard !didConfirmThisSet,
              let family = observation.family,
              observation.isWorkContext || observation.finalizePass,
              observation.sampleCount >= minSamples,
              observation.detectedRepCount >= Defaults.minDetectedReps else {
            updateStability(with: observation.detectedRepCount)
            return NarrowRepEvaluateResult(
                detectedRepCount: observation.detectedRepCount,
                topCandidate: nil,
                confidence: 0,
                proposal: nil
            )
        }

        updateStability(with: observation.detectedRepCount)

        let candidates = Self.rankCandidates(
            detected: observation.detectedRepCount,
            planned: observation.plannedReps
        )
        guard let top = candidates.first else {
            return NarrowRepEvaluateResult(
                detectedRepCount: observation.detectedRepCount,
                topCandidate: nil,
                confidence: 0,
                proposal: nil
            )
        }

        let confidence = scoreToConfidence(top.score, planned: observation.plannedReps, suggested: top.reps)
        let stableEnough = observation.finalizePass || stablePassCount >= stabilityPasses

        guard confidence >= promptConfidenceThreshold,
              stableEnough,
              !isCoolingDown(suggested: top.reps, now: observation.now) else {
            return NarrowRepEvaluateResult(
                detectedRepCount: observation.detectedRepCount,
                topCandidate: top,
                confidence: confidence,
                proposal: nil
            )
        }

        let proposal = NarrowRepProposal(
            suggestedReps: top.reps,
            plannedReps: observation.plannedReps,
            detectedRepCount: observation.detectedRepCount,
            confidence: confidence,
            family: family,
            rankedCandidates: candidates
        )
        pendingProposal = proposal
        proposalPresentedAt = observation.now

        return NarrowRepEvaluateResult(
            detectedRepCount: observation.detectedRepCount,
            topCandidate: top,
            confidence: confidence,
            proposal: proposal
        )
    }

    // MARK: - Ranking

    /// Prefer detected count, then plan agreement, then neighbors — minimize correction distance.
    static func rankCandidates(detected: Int, planned: Int?) -> [NarrowRepCandidate] {
        guard detected >= Defaults.minDetectedReps else { return [] }
        if let planned, abs(detected - planned) > Defaults.maxDistanceFromPlan {
            // Detection too far from plan — do not invent a ranked suggestion from noise.
            return []
        }

        var scored: [NarrowRepCandidate] = []

        func add(_ reps: Int, source: NarrowRepCandidate.Source, base: Double) {
            guard reps >= 1 else { return }
            if let planned, abs(reps - planned) > Defaults.maxDistanceFromPlan {
                return
            }
            var score = base
            if let planned {
                let distance = abs(reps - planned)
                score += max(0, 0.28 - Double(distance) * 0.07)
                if reps == planned { score += 0.12 }
            }
            scored.append(NarrowRepCandidate(reps: reps, score: score, source: source))
        }

        add(detected, source: .detected, base: 0.62)
        if let planned, planned != detected {
            add(planned, source: .planned, base: 0.48)
        }
        add(detected - 1, source: .neighbor, base: 0.40)
        add(detected + 1, source: .neighbor, base: 0.40)

        // Deduplicate by reps keeping highest score.
        var bestByReps: [Int: NarrowRepCandidate] = [:]
        for candidate in scored {
            if let existing = bestByReps[candidate.reps] {
                if candidate.score > existing.score {
                    bestByReps[candidate.reps] = candidate
                }
            } else {
                bestByReps[candidate.reps] = candidate
            }
        }

        return bestByReps.values.sorted {
            // Always surface detected first when present — plan/neighbors are ranked alternatives.
            if $0.source == .detected && $1.source != .detected { return true }
            if $1.source == .detected && $0.source != .detected { return false }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.reps < $1.reps
        }
    }

    // MARK: - Private

    private mutating func updateStability(with detected: Int) {
        if detected == lastStableCount {
            stablePassCount += 1
        } else {
            lastStableCount = detected
            stablePassCount = detected >= Defaults.minDetectedReps ? 1 : 0
        }
    }

    private func isCoolingDown(suggested: Int, now: Date) -> Bool {
        guard let lastRejectAt,
              now.timeIntervalSince(lastRejectAt) < rejectCooldownSeconds else {
            return false
        }
        // Cooldown only blocks the same rejected suggestion.
        return lastRejectedReps == suggested
    }

    private func scoreToConfidence(_ score: Double, planned: Int?, suggested: Int) -> Double {
        var confidence = min(0.98, max(0, score))
        if let planned {
            let distance = abs(suggested - planned)
            if distance == 0 {
                confidence = max(confidence, 0.86)
            } else if distance >= 3 {
                confidence = min(confidence, 0.78)
            }
        }
        return confidence
    }
}
