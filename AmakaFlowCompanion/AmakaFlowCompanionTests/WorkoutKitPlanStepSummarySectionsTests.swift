//
//  WorkoutKitPlanStepSummarySectionsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2378 Task 7 — preview fidelity: multi-step mobility, skipped-ramp
//  captions, amber open goals, and cooldown-band-last section grouping for
//  `WorkoutKitPlanStepSummary.sections(from:)`.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutKitPlanStepSummarySectionsTests: XCTestCase {
    private func plan(_ intervalsJSON: String, sportType: String = "traditionalStrengthTraining") -> Data {
        Data("""
        {
          "title": "Test workout",
          "sportType": "\(sportType)",
          "intervals": [\(intervalsJSON)]
        }
        """.utf8)
    }

    // MARK: - Multi-step mobility prep

    func testMultiStepMobilityBeforeWorkGroupsIntoOneNumberedBand() {
        let json = plan("""
        { "kind": "work", "name": "Jump Rope", "seconds": 120 },
        { "kind": "work", "name": "World's Greatest Stretch", "reps": 5 },
        { "kind": "work", "name": "Barbell back squat", "reps": 10 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let mobility = sections.first(where: { $0.accent == .mobility }) else {
            return XCTFail("Expected a Mobility prep band")
        }
        XCTAssertEqual(mobility.band, "Mobility prep")
        XCTAssertEqual(mobility.steps.map(\.title), ["Jump Rope", "World's Greatest Stretch"])
        XCTAssertEqual(mobility.steps.map(\.number), [1, 2])
    }

    // MARK: - Per-exercise ramp vs skipped

    func testExerciseWithWarmupRowsHasNoSkippedCaption() {
        let json = plan("""
        { "kind": "work", "name": "WU · Barbell back squat", "reps": 8 },
        { "kind": "work", "name": "Barbell back squat", "reps": 5 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let exercise = sections.first(where: { $0.accent == .work }) else {
            return XCTFail("Expected a work band")
        }
        XCTAssertNil(exercise.caption)
    }

    func testExerciseWithNoWarmupRowsGetsSkippedCaption() {
        let json = plan("""
        { "kind": "work", "name": "Overhead Press", "reps": 5 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let exercise = sections.first(where: { $0.accent == .work }) else {
            return XCTFail("Expected a work band")
        }
        XCTAssertEqual(exercise.caption, WorkoutEnrichmentPushCopy.noWarmupsYourCall)
        XCTAssertEqual(WorkoutEnrichmentPushCopy.noWarmupsYourCall, "NO WARM-UPS — YOUR CALL")
    }

    // MARK: - Amber open goals

    func testOpenGoalWorkStepSurfacesOpenDetail() {
        let json = plan("""
        { "kind": "work", "name": "Farmer's Carry" }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let step = sections.first(where: { $0.accent == .work })?.steps.first else {
            return XCTFail("Expected a work step")
        }
        XCTAssertEqual(step.detail, "OPEN")
        XCTAssertTrue(step.isOpenGoal)
    }

    func testOpenRestChipIsFlaggedOpen() {
        let json = plan("""
        { "kind": "work", "name": "Deadlift", "reps": 5 },
        { "kind": "rest" }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let step = sections.first(where: { $0.accent == .work })?.steps.first else {
            return XCTFail("Expected a work step")
        }
        XCTAssertEqual(step.restChip, "REST · YOU END IT")
        XCTAssertTrue(step.isOpenRest)
    }

    func testTimedGoalIsNotFlaggedOpen() {
        let json = plan("""
        { "kind": "work", "name": "Plank", "seconds": 45 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let step = sections.first(where: { $0.accent == .work })?.steps.first else {
            return XCTFail("Expected a work step")
        }
        XCTAssertFalse(step.isOpenGoal)
        XCTAssertEqual(step.detail, "45S")
    }

    // MARK: - Cooldown band last

    func testMultiStepCooldownAfterWorkGroupsIntoTrailingCooldownBand() {
        // Mirrors mapper `_compose_soft_activity_blocks` — multi-activity
        // cooldown emits named steps with no `kind: cooldown` marker.
        let json = plan("""
        { "kind": "work", "name": "Barbell back squat", "reps": 10 },
        { "kind": "work", "name": "Foam Roll" },
        { "kind": "work", "name": "Jump Rope", "seconds": 180 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        XCTAssertEqual(sections.last?.accent, .cooldown)
        XCTAssertEqual(sections.last?.band, "Cool-down")
        XCTAssertEqual(sections.last?.steps.map(\.title), ["Foam Roll", "Jump Rope"])
    }

    func testExplicitCooldownIntervalStillLandsLast() {
        let json = plan("""
        { "kind": "work", "name": "Barbell back squat", "reps": 10 },
        { "kind": "cooldown", "seconds": 300 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        XCTAssertEqual(sections.last?.accent, .cooldown)
        XCTAssertEqual(sections.last?.steps.map(\.title), ["Cool-down"])
        XCTAssertEqual(sections.last?.steps.first?.detail, "5 MIN")
    }

    func testExplicitOpenCooldownSurfacesOpenNotZeroSeconds() {
        // Legacy singular cooldown encodes an open goal as seconds: 0.
        let json = plan("""
        { "kind": "work", "name": "Barbell back squat", "reps": 10 },
        { "kind": "cooldown", "seconds": 0 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        XCTAssertEqual(sections.last?.steps.first?.detail, "OPEN")
    }

    func testMobilityTokenSandwichedBetweenWorkIsInterstitialNotDropped() {
        // "Jump Rope" mid-workout looks like a soft activity but more work
        // follows — it must resurface as a mobility band, not vanish.
        let json = plan("""
        { "kind": "work", "name": "Barbell back squat", "reps": 10 },
        { "kind": "work", "name": "Jump Rope", "seconds": 60 },
        { "kind": "work", "name": "Overhead Press", "reps": 8 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        let mobilityBands = sections.filter { $0.accent == .mobility }
        XCTAssertEqual(mobilityBands.count, 1)
        XCTAssertEqual(mobilityBands.first?.steps.map(\.title), ["Jump Rope"])
        XCTAssertNotEqual(sections.last?.accent, .mobility, "mid-workout break must not be misread as the final band")
    }
}
