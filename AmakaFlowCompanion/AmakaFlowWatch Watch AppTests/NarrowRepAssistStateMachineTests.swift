//
//  NarrowRepAssistStateMachineTests.swift
//  AmakaFlowWatch Watch AppTests
//
//  AMA-2420 Phase 5 — family gating, ranking, never silent commit.
//

@testable import AmakaFlowWatch_Watch_App
import XCTest

final class NarrowRepAssistStateMachineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Family resolve

    func test_family_resolvesCurlPressRowSwing() {
        XCTAssertEqual(NarrowRepExerciseFamily.resolve(exerciseName: "Barbell Curl"), .curl)
        XCTAssertEqual(NarrowRepExerciseFamily.resolve(exerciseName: "DB Bench Press"), .press)
        XCTAssertEqual(NarrowRepExerciseFamily.resolve(exerciseName: "Seated Row"), .row)
        XCTAssertEqual(NarrowRepExerciseFamily.resolve(exerciseName: "KB Swing"), .swing)
    }

    func test_family_unsupported_returnsNil() {
        XCTAssertNil(NarrowRepExerciseFamily.resolve(exerciseName: "Back Squat"))
        XCTAssertNil(NarrowRepExerciseFamily.resolve(exerciseName: "Deadlift"))
        XCTAssertNil(NarrowRepExerciseFamily.resolve(exerciseName: "Lunges"))
    }

    // MARK: - Ranking

    func test_rankCandidates_prefersDetected_whenCloseToPlan() {
        let ranked = NarrowRepAssistStateMachine.rankCandidates(detected: 8, planned: 8)
        XCTAssertEqual(ranked.first?.reps, 8)
        XCTAssertEqual(ranked.first?.source, .detected)
    }

    func test_rankCandidates_includesPlan_whenDetectedDiffers() {
        let ranked = NarrowRepAssistStateMachine.rankCandidates(detected: 7, planned: 8)
        XCTAssertTrue(ranked.contains { $0.reps == 7 && $0.source == .detected })
        XCTAssertTrue(ranked.contains { $0.reps == 8 && $0.source == .planned })
    }

    func test_rankCandidates_dropsFarFromPlan() {
        let ranked = NarrowRepAssistStateMachine.rankCandidates(detected: 20, planned: 8)
        XCTAssertTrue(ranked.isEmpty, "Far detections must not become candidates")
    }

    // MARK: - Proposal gating

    func test_unsupportedFamily_neverProposes() {
        var machine = NarrowRepAssistStateMachine(stabilityPasses: 1)
        let result = machine.evaluate(observation(
            family: nil,
            planned: 10,
            detected: 10,
            samples: 100
        ))
        XCTAssertNil(result.proposal)
        XCTAssertNil(machine.pendingProposal)
    }

    func test_lowSamples_neverProposes() {
        var machine = NarrowRepAssistStateMachine(stabilityPasses: 1)
        let result = machine.evaluate(observation(
            family: .curl,
            planned: 10,
            detected: 10,
            samples: 5
        ))
        XCTAssertNil(result.proposal)
    }

    func test_stableDetectedMatchingPlan_proposes_withoutMutatingUntilConfirm() {
        var machine = NarrowRepAssistStateMachine(stabilityPasses: 2)
        _ = machine.evaluate(observation(family: .curl, planned: 8, detected: 8, samples: 80))
        XCTAssertNil(machine.pendingProposal, "Needs stability passes")

        let result = machine.evaluate(observation(family: .curl, planned: 8, detected: 8, samples: 80))
        XCTAssertNotNil(result.proposal)
        XCTAssertEqual(result.proposal?.suggestedReps, 8)
        XCTAssertEqual(result.proposal?.detectionMethod, "autoConfirmed")
        // Still pending — confirm required (never silent).
        XCTAssertNotNil(machine.pendingProposal)
        XCTAssertEqual(machine.confirmPendingProposal()?.suggestedReps, 8)
        XCTAssertNil(machine.pendingProposal)
    }

    func test_finalizePass_canProposeWithoutExtraStability() {
        var machine = NarrowRepAssistStateMachine(stabilityPasses: 5)
        let result = machine.evaluate(observation(
            family: .row,
            planned: 10,
            detected: 10,
            samples: 90,
            finalize: true
        ))
        XCTAssertNotNil(result.proposal)
        XCTAssertEqual(result.proposal?.suggestedReps, 10)
    }

    func test_reject_entersCooldown_forSameSuggestion() {
        var machine = NarrowRepAssistStateMachine(
            rejectCooldownSeconds: 20,
            stabilityPasses: 1
        )
        _ = machine.evaluate(observation(
            family: .press,
            planned: 8,
            detected: 8,
            samples: 80,
            timestamp: now
        ))
        XCTAssertNotNil(machine.pendingProposal)
        machine.rejectPendingProposal(at: now)
        XCTAssertNil(machine.pendingProposal)

        let duringCooldown = machine.evaluate(observation(
            family: .press,
            planned: 8,
            detected: 8,
            samples: 80,
            timestamp: now.addingTimeInterval(5)
        ))
        XCTAssertNil(duringCooldown.proposal)

        let afterCooldown = machine.evaluate(observation(
            family: .press,
            planned: 8,
            detected: 8,
            samples: 80,
            timestamp: now.addingTimeInterval(25)
        ))
        XCTAssertNotNil(afterCooldown.proposal)
    }

    func test_inferred_whenSuggestionDiffersFromPlan() {
        var machine = NarrowRepAssistStateMachine(stabilityPasses: 1)
        let result = machine.evaluate(observation(
            family: .swing,
            planned: 12,
            detected: 10,
            samples: 100,
            finalize: true
        ))
        XCTAssertEqual(result.proposal?.detectionMethod, "inferred")
        XCTAssertEqual(result.proposal?.suggestedReps, 10)
    }

    func test_beginSet_clearsPriorConfirmGate() {
        var machine = NarrowRepAssistStateMachine(stabilityPasses: 1)
        _ = machine.evaluate(observation(
            family: .curl,
            planned: 8,
            detected: 8,
            samples: 80,
            finalize: true
        ))
        _ = machine.confirmPendingProposal()

        // Confirmed this set — no further proposals until beginSet.
        let blocked = machine.evaluate(observation(
            family: .curl,
            planned: 8,
            detected: 9,
            samples: 80,
            finalize: true
        ))
        XCTAssertNil(blocked.proposal)

        machine.beginSet()
        let next = machine.evaluate(observation(
            family: .curl,
            planned: 8,
            detected: 8,
            samples: 80,
            finalize: true
        ))
        XCTAssertNotNil(next.proposal)
    }

    // MARK: - Helpers

    private func observation(
        family: NarrowRepExerciseFamily?,
        planned: Int?,
        detected: Int,
        samples: Int,
        finalize: Bool = false,
        timestamp: Date? = nil
    ) -> NarrowRepObservation {
        NarrowRepObservation(
            family: family,
            plannedReps: planned,
            detectedRepCount: detected,
            sampleCount: samples,
            isWorkContext: true,
            finalizePass: finalize,
            now: timestamp ?? now
        )
    }
}
