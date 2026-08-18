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
    // MARK: - AMA-2454 named native warmup

    func testNamedNativeWarmupIntervalShowsAuthoredExerciseInPreviewSections() {
        let json = plan("""
        { "kind": "warmup", "seconds": 300 }
        """, warmupDisplayName: "Ski Erg")
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let mobility = sections.first(where: { $0.accent == .mobility }) else {
            return XCTFail("Expected mobility band for native warmup")
        }
        XCTAssertEqual(
            mobility.steps.map(\.title), ["Ski Erg"],
            "a named native warm-up must show the authored exercise, not generic Warm-up (AMA-2454)"
        )
        XCTAssertEqual(mobility.steps.first?.detail, "5 MIN", "warm-up detail stays the duration label")
    }

    func testNativeWarmupWithoutDisplayNameFallsBackToWarmUpTitle() {
        let json = plan("""
        { "kind": "warmup", "seconds": 300 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let mobility = sections.first(where: { $0.accent == .mobility }) else {
            return XCTFail("Expected mobility band for native warmup")
        }
        XCTAssertEqual(
            mobility.steps.map(\.title), ["Warm-up"],
            "no authored name → the generic Warm-up title is unchanged"
        )
        XCTAssertEqual(mobility.steps.first?.detail, "5 MIN", "warm-up detail stays the duration label")
    }

    func testNamedNativeWarmupSummaryLineUsesAuthoredExercise() {
        let json = plan("""
        { "kind": "warmup", "seconds": 300 }
        """, warmupDisplayName: "Ski Erg")
        let lines = WorkoutKitPlanStepSummary.lines(from: json)
        XCTAssertTrue(
            lines.contains("Ski Erg · 300s"),
            "the summary line must carry the authored warm-up exercise (AMA-2454)"
        )
        XCTAssertFalse(
            lines.contains("Warm-up · 300s"),
            "the generic label must not appear when an authored name exists"
        )
    }

    private func plan(
        _ intervalsJSON: String,
        sportType: String = "traditionalStrengthTraining",
        warmupDisplayName: String? = nil
    ) -> Data {
        let warmupBlock: String
        if let warmupDisplayName {
            warmupBlock = """
            "warmup": {
              "goal": { "kind": "time", "seconds": 300 },
              "displayName": "\(warmupDisplayName)"
            },
            """
        } else {
            warmupBlock = ""
        }
        return Data("""
        {
          "title": "Test workout",
          "sportType": "\(sportType)",
          \(warmupBlock)
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

    // MARK: - AMA-2423 station Transitions (not Rest)

    /// Brief step 1 — mapper names the recovery step "Transition" for
    /// station_transition intent; preview must show a Transition chip, not Rest.
    func testOpenTransitionChipShowsTransitionNotRest() {
        let json = plan("""
        { "kind": "work", "name": "Ski Erg", "reps": 500 },
        { "kind": "rest", "name": "Transition" }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let step = sections.first(where: { $0.accent == .work })?.steps.first else {
            return XCTFail("Expected a work step")
        }
        XCTAssertEqual(step.restChip, "TRANSITION · YOU END IT")
        XCTAssertTrue(step.isOpenRest, "open Transition must still read amber \"you end it\"")
    }

    /// Timed Transitions (a fixed `transitionSec`) get the same `TRANSITION Ns`
    /// treatment as timed Rest — and must not be flagged open/amber.
    func testTimedTransitionChipIsNotFlaggedOpen() {
        let json = plan("""
        { "kind": "work", "name": "Row", "reps": 500 },
        { "kind": "rest", "name": "Transition", "seconds": 45 }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let step = sections.first(where: { $0.accent == .work })?.steps.first else {
            return XCTFail("Expected a work step")
        }
        XCTAssertEqual(step.restChip, "TRANSITION 45S")
        XCTAssertFalse(step.isOpenRest)
    }

    /// Dogfood step 4 — a Transition after every station must show on every
    /// station. The flattener used to hang one chip off the end of the band, so
    /// only the last station carried it.
    func testCircuitPinsTransitionChipToEachStation() {
        let json = plan("""
        {
          "kind": "repeat",
          "reps": 4,
          "intervals": [
            { "kind": "time", "seconds": 30, "name": "Ski Erg" },
            { "kind": "rest", "name": "Transition", "seconds": 20 },
            { "kind": "time", "seconds": 30, "name": "Row" },
            { "kind": "rest", "name": "Transition", "seconds": 20 },
            { "kind": "time", "seconds": 30, "name": "Bike" },
            { "kind": "rest", "name": "Transition", "seconds": 20 }
          ]
        }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let circuit = sections.first(where: { $0.band == "Circuit" }) else {
            return XCTFail("Expected a Circuit band, got \(sections.map(\.band))")
        }
        XCTAssertEqual(circuit.steps.map(\.title), ["Ski Erg", "Row", "Bike"])
        XCTAssertEqual(
            circuit.steps.map(\.restChip),
            ["TRANSITION 20S", "TRANSITION 20S", "TRANSITION 20S"]
        )
    }

    /// A circuit with one end-of-round rest keeps the pre-AMA-2423 shape: the
    /// chip lands on the last station and nowhere else.
    func testCircuitWithEndOfRoundRestKeepsSingleTrailingChip() {
        let json = plan("""
        {
          "kind": "repeat",
          "reps": 3,
          "intervals": [
            { "kind": "time", "seconds": 30, "name": "Ski Erg" },
            { "kind": "time", "seconds": 30, "name": "Row" },
            { "kind": "rest", "seconds": 90 }
          ]
        }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let circuit = sections.first(where: { $0.band == "Circuit" }) else {
            return XCTFail("Expected a Circuit band, got \(sections.map(\.band))")
        }
        XCTAssertEqual(circuit.steps.map(\.restChip), [nil, "REST 90S"])
    }

    /// A plain, unnamed recovery step must keep reading Rest — only a
    /// `displayName == "Transition"` recovery flips to the Transition chip.
    func testPlainRestStepIsUnaffectedByTransitionCopy() {
        let json = plan("""
        { "kind": "work", "name": "Deadlift", "reps": 5 },
        { "kind": "rest" }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let step = sections.first(where: { $0.accent == .work })?.steps.first else {
            return XCTFail("Expected a work step")
        }
        XCTAssertEqual(step.restChip, "REST · YOU END IT")
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

    // MARK: - AMA-2408 dogfood — intensity labels + multi-ramp blocks

    /// Mapper packs N warm-up steps into one iterations=1 block. Preview must
    /// fold them under the exercise band — not a orphan Circuit with
    /// "NO WARM-UPS" on the working sets.
    func testWarmupOnlyRepeatBandsUnderExerciseNotCircuit() {
        let json = plan("""
        {
          "kind": "repeat",
          "reps": 1,
          "intervals": [
            { "kind": "reps", "reps": 11, "name": "Warm-up · Incline Smith Machine Press" },
            { "kind": "reps", "reps": 11, "name": "Warm-up · Incline Smith Machine Press" }
          ]
        },
        {
          "kind": "repeat",
          "reps": 5,
          "intervals": [
            { "kind": "reps", "reps": 10, "name": "Incline Smith Machine Press" }
          ]
        }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        XCTAssertFalse(
            sections.contains { $0.band == "Circuit" },
            "warm-up-only blocks must not render as Circuit"
        )
        guard let incline = sections.first(where: {
            $0.accent == .work && $0.band == "Incline Smith Machine Press"
        }) else {
            return XCTFail("Expected Incline Smith work band")
        }
        XCTAssertNil(incline.caption, "ramp rows under the band clear NO WARM-UPS")
        XCTAssertEqual(
            incline.steps.filter { $0.title == PreviewStep.warmupSetTitle }.count,
            2
        )
        XCTAssertEqual(
            incline.steps.filter { $0.title == PreviewStep.warmupSetTitle }.map(\.detail),
            ["11 REPS", "11 REPS"]
        )
    }

    /// Intensity-suffixed warm-up labels must still family-match the working sets,
    /// and "1 REPS" from open-goal coerce must not win over a recoverable note.

    /// Two same-reps ramp rows must both render — identical detail must not
    /// collapse to a single Warm-up set (AMA-2408 dogfood).
    func testTwoIdenticalWarmupRampsBothAppearUnderExercise() {
        let json = plan("""
        {
          "kind": "repeat",
          "reps": 1,
          "intervals": [
            { "kind": "reps", "reps": 10, "name": "Warm-up · Back Squat · 10" },
            { "kind": "rest" },
            { "kind": "reps", "reps": 10, "name": "Warm-up · Back Squat · 10" },
            { "kind": "rest" }
          ]
        },
        {
          "kind": "repeat",
          "reps": 4,
          "intervals": [
            { "kind": "reps", "reps": 8, "name": "Back Squat" },
            { "kind": "rest" }
          ]
        }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        guard let squat = sections.first(where: {
            $0.accent == .work && $0.band == "Back Squat"
        }) else {
            return XCTFail("Expected Back Squat band")
        }
        let warmups = squat.steps.filter { $0.title == PreviewStep.warmupSetTitle }
        XCTAssertEqual(warmups.count, 2, "both ramp sets must appear; got \(squat.steps.map { "\($0.number):\($0.title)" })")
        XCTAssertEqual(warmups.map(\.detail), ["10 REPS", "10 REPS"])
        XCTAssertEqual(squat.tag, "6 SETS")
    }

    /// Build-reveal must not collapse two identical warm-up beats onto step #1.
    func testRevealKeepsBothIdenticalWarmupRows() {
        let json = plan("""
        {
          "kind": "repeat",
          "reps": 1,
          "intervals": [
            { "kind": "reps", "reps": 10, "name": "Warm-up · Back Squat · 10" },
            { "kind": "reps", "reps": 10, "name": "Warm-up · Back Squat · 10" }
          ]
        },
        {
          "kind": "repeat",
          "reps": 4,
          "intervals": [
            { "kind": "reps", "reps": 8, "name": "Back Squat" }
          ]
        }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        let beats = BuildRevealScripts.watchPreview(sections: sections).beats
        let revealed = AppleWatchPreviewReveal.sections(from: sections, shownBeats: beats)
        guard let squat = revealed.first(where: { $0.band == "Back Squat" }) else {
            return XCTFail("Expected revealed Back Squat band")
        }
        XCTAssertEqual(
            squat.steps.filter { $0.title == PreviewStep.warmupSetTitle }.count,
            2,
            "reveal must keep both identical warm-up ramps"
        )
        XCTAssertEqual(squat.steps.map(\.number).sorted(), squat.steps.map(\.number))
        XCTAssertEqual(Set(squat.steps.map(\.number)).count, squat.steps.count)
    }

    /// Pure unit: identical title+detail must advance to the next unused step number.
    func testNextUnusedStepDoesNotRebindFirstIdenticalWarmup() {
        let steps = [
            PreviewStep(number: 1, title: PreviewStep.warmupSetTitle, detail: "10 REPS", restChip: nil),
            PreviewStep(number: 2, title: PreviewStep.warmupSetTitle, detail: "10 REPS", restChip: nil),
            PreviewStep(number: 3, title: "Back Squat", detail: "8 REPS", restChip: nil),
        ]
        let beat = BuildBeat(kind: .row, name: PreviewStep.warmupSetTitle, detail: "10 REPS")

        let first = AppleWatchPreviewReveal.nextUnusedStep(
            in: steps, matching: beat, alreadyShown: []
        )
        XCTAssertEqual(first?.number, 1)

        let second = AppleWatchPreviewReveal.nextUnusedStep(
            in: steps, matching: beat, alreadyShown: [first!]
        )
        XCTAssertEqual(second?.number, 2, "second identical ramp must consume step #2, not rebind #1")

        let third = AppleWatchPreviewReveal.nextUnusedStep(
            in: steps, matching: beat, alreadyShown: [first!, second!]
        )
        XCTAssertNil(third, "no third identical warm-up left")
    }

    /// Reveal assembly with hand-built beats (no script dependency).
    func testRevealSectionsConsumesIdenticalRowsInOrder() {
        let section = PreviewSection(
            accent: .work,
            band: "Back Squat",
            tag: "6 SETS",
            steps: [
                PreviewStep(number: 1, title: PreviewStep.warmupSetTitle, detail: "10 REPS", restChip: nil),
                PreviewStep(number: 2, title: PreviewStep.warmupSetTitle, detail: "10 REPS", restChip: nil),
                PreviewStep(number: 3, title: "Back Squat", detail: "8 REPS", restChip: nil),
            ]
        )
        let beats: [BuildBeat] = [
            BuildBeat(kind: .band, label: "Back Squat"),
            BuildBeat(kind: .row, name: PreviewStep.warmupSetTitle, detail: "10 REPS"),
            BuildBeat(kind: .row, name: PreviewStep.warmupSetTitle, detail: "10 REPS"),
            BuildBeat(kind: .row, name: "Back Squat", detail: "8 REPS"),
        ]
        let revealed = AppleWatchPreviewReveal.sections(from: [section], shownBeats: beats)
        XCTAssertEqual(revealed.count, 1)
        XCTAssertEqual(revealed[0].steps.map(\.number), [1, 2, 3])
        XCTAssertEqual(
            revealed[0].steps.map(\.title),
            [PreviewStep.warmupSetTitle, PreviewStep.warmupSetTitle, "Back Squat"]
        )
    }

    func testIntensityLabeledWarmupsBandAndAvoidFakeOneRep() {
        let json = plan("""
        {
          "kind": "repeat",
          "reps": 1,
          "intervals": [
            {
              "kind": "reps",
              "reps": 1,
              "name": "Warm-up · Machine Lateral Raises · LIGHT · ~40%"
            },
            {
              "kind": "reps",
              "reps": 1,
              "name": "Warm-up · Machine Lateral Raises · MODERATE · ~60%"
            }
          ]
        },
        {
          "kind": "repeat",
          "reps": 3,
          "intervals": [
            { "kind": "reps", "reps": 12, "name": "Machine Lateral Raises" }
          ]
        }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        guard let mlr = sections.first(where: {
            $0.accent == .work && $0.band == "Machine Lateral Raises"
        }) else {
            return XCTFail("Expected Machine Lateral Raises band with ramps attached")
        }
        XCTAssertNil(mlr.caption)
        let rampDetails = mlr.steps
            .filter { $0.title == PreviewStep.warmupSetTitle }
            .map(\.detail)
        XCTAssertEqual(rampDetails, ["LIGHT · ~40%", "MODERATE · ~60%"])
        XCTAssertFalse(rampDetails.contains("1 REPS"))
    }

    /// Multi-token exercise names must not leak into the intensity note suffix.
    func testIntensityNoteDropsExerciseNameSegments() {
        let json = plan("""
        {
          "kind": "repeat",
          "reps": 1,
          "intervals": [
            {
              "kind": "reps",
              "reps": 1,
              "name": "Warm-up · Dumbbell · Shoulder Press · LIGHT · ~40%"
            }
          ]
        },
        {
          "kind": "repeat",
          "reps": 3,
          "intervals": [
            { "kind": "reps", "reps": 12, "name": "Dumbbell · Shoulder Press" }
          ]
        }
        """)
        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        guard let band = sections.first(where: {
            $0.accent == .work && $0.band.contains("Shoulder Press")
        }) else {
            return XCTFail("Expected Shoulder Press band")
        }
        let warmup = band.steps.first { $0.title == PreviewStep.warmupSetTitle }
        XCTAssertEqual(warmup?.detail, "LIGHT · ~40%")
        XCTAssertFalse(
            (warmup?.detail ?? "").contains("Shoulder Press"),
            "exercise-name tokens must not leak into intensity detail"
        )
    }
}
