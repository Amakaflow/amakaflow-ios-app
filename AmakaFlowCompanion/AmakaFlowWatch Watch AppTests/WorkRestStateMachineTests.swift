//
//  WorkRestStateMachineTests.swift
//  AmakaFlowWatch Watch AppTests
//
//  AMA-2420 Phase 4 — work/rest confidence gating + confirm/reject.
//

@testable import AmakaFlowWatch_Watch_App
import XCTest

final class WorkRestStateMachineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func test_startsInIdleRest_byDefault() {
        let machine = WorkRestStateMachine()
        XCTAssertEqual(machine.phase, .idleRest)
        XCTAssertNil(machine.pendingProposal)
    }

    func test_lowMotion_whileResting_doesNotPropose() {
        var machine = WorkRestStateMachine(phase: .idleRest)
        let result = machine.evaluate(observation(activity: 0.10, samples: 40))
        XCTAssertEqual(result.inferredPhase, .idleRest)
        XCTAssertNil(result.proposal)
        XCTAssertNil(machine.pendingProposal)
    }

    func test_highMotion_whileResting_proposesWork_whenConfident() {
        var machine = WorkRestStateMachine(phase: .idleRest)
        let result = machine.evaluate(observation(activity: 0.95, samples: 50))
        XCTAssertEqual(result.inferredPhase, .workSet)
        XCTAssertNotNil(result.proposal)
        XCTAssertEqual(result.proposal?.transition, .toWorkSet)
        XCTAssertGreaterThanOrEqual(result.proposal?.confidence ?? 0, WorkRestStateMachine.Defaults.promptConfidenceThreshold)
        // Phase must not change until confirm (never silent invent).
        XCTAssertEqual(machine.phase, .idleRest)
    }

    func test_borderlineMotion_doesNotPrompt_evenWithElevatedHR() {
        var machine = WorkRestStateMachine(phase: .idleRest)
        // Activity just above work threshold but motion confidence stays below floor.
        let result = machine.evaluate(observation(activity: 0.45, samples: 50, heartRate: 140))
        XCTAssertEqual(result.inferredPhase, .workSet)
        XCTAssertNil(result.proposal, "HR must not invent a prompt from weak motion")
    }

    func test_elevatedHR_canNudge_nearThresholdMotion_intoPrompt() {
        var machine = WorkRestStateMachine(phase: .idleRest)
        // Choose activity so motionConfidence is ≥ floor (0.67) but below 0.72 without HR.
        // motionConfidence = 0.55 + ((activity - 0.42) / 0.58) * 0.45
        // Want ~0.70: (activity - 0.42) / 0.58 = 0.333 → activity ≈ 0.613
        let withoutHR = machine.evaluate(observation(activity: 0.613, samples: 50, heartRate: nil))
        XCTAssertNil(withoutHR.proposal)

        machine = WorkRestStateMachine(phase: .idleRest)
        let withHR = machine.evaluate(observation(activity: 0.613, samples: 50, heartRate: 125))
        XCTAssertNotNil(withHR.proposal)
        XCTAssertTrue(withHR.proposal?.usedHeartRateContext == true)
    }

    func test_lowSampleCount_producesNoProposal() {
        var machine = WorkRestStateMachine(phase: .idleRest)
        let result = machine.evaluate(observation(activity: 0.99, samples: 5))
        XCTAssertNil(result.proposal)
        XCTAssertEqual(result.confidence, 0)
    }

    func test_quietMotion_whileWorking_proposesRest() {
        var machine = WorkRestStateMachine(phase: .workSet)
        let result = machine.evaluate(observation(activity: 0.02, samples: 50))
        XCTAssertEqual(result.inferredPhase, .idleRest)
        XCTAssertEqual(result.proposal?.transition, .toIdleRest)
        XCTAssertEqual(machine.phase, .workSet)
    }

    func test_confirmProposal_appliesTransition() {
        var machine = WorkRestStateMachine(phase: .idleRest)
        _ = machine.evaluate(observation(activity: 0.95, samples: 50))
        XCTAssertNotNil(machine.pendingProposal)

        let applied = machine.confirmPendingProposal()
        XCTAssertEqual(applied, .toWorkSet)
        XCTAssertEqual(machine.phase, .workSet)
        XCTAssertNil(machine.pendingProposal)
    }

    func test_rejectProposal_keepsPhase_andCooldownBlocksReprompt() {
        var machine = WorkRestStateMachine(phase: .idleRest)
        _ = machine.evaluate(observation(activity: 0.95, samples: 50, timestamp: now))
        XCTAssertNotNil(machine.pendingProposal)

        machine.rejectPendingProposal(now: now)
        XCTAssertEqual(machine.phase, .idleRest)
        XCTAssertNil(machine.pendingProposal)

        let soon = now.addingTimeInterval(5)
        let again = machine.evaluate(observation(activity: 0.95, samples: 50, timestamp: soon))
        XCTAssertNil(again.proposal, "Reject cooldown should suppress re-prompt")

        let later = now.addingTimeInterval(WorkRestStateMachine.Defaults.rejectCooldownSeconds + 1)
        let afterCooldown = machine.evaluate(observation(activity: 0.95, samples: 50, timestamp: later))
        XCTAssertNotNil(afterCooldown.proposal)
    }

    func test_syncPhase_clearsPendingProposal() {
        var machine = WorkRestStateMachine(phase: .idleRest)
        _ = machine.evaluate(observation(activity: 0.95, samples: 50))
        XCTAssertNotNil(machine.pendingProposal)

        machine.syncPhase(.workSet)
        XCTAssertEqual(machine.phase, .workSet)
        XCTAssertNil(machine.pendingProposal)
    }

    func test_activityScore_higherForActiveSamples() {
        let quiet = (0..<40).map { sampleIndex in
            IMUSample(accX: 0.01, accY: 0.01, accZ: 0.01, gyrX: 0, gyrY: 0, gyrZ: 0, timestamp: Double(sampleIndex) * 0.02)
        }
        let active = (0..<40).map { sampleIndex in
            IMUSample(accX: 0.4, accY: -0.5, accZ: 0.3, gyrX: 1.0, gyrY: 0.8, gyrZ: 0.5, timestamp: Double(sampleIndex) * 0.02)
        }
        XCTAssertGreaterThan(
            WorkRestMotionMetrics.activityScore(from: active),
            WorkRestMotionMetrics.activityScore(from: quiet)
        )
    }

    // MARK: - Helpers

    private func observation(
        activity: Double,
        samples: Int,
        heartRate: Double? = nil,
        timestamp: Date? = nil
    ) -> WorkRestObservation {
        WorkRestObservation(
            activityScore: activity,
            sampleCount: samples,
            heartRateBPM: heartRate,
            now: timestamp ?? now
        )
    }
}
