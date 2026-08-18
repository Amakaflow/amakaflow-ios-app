//
//  WorkoutEnrichmentPushCopyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2371: Peloton-style toggle-row copy for the enhance sheet
//  (spec 2026-08-02 send/enhance flow iOS UI redesign).
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutEnrichmentPushCopyTests: XCTestCase {
    func testWatchReadyTitle() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.sheetTitle, "Make it watch-ready?")
    }

    func testPrimaryCTACountsCheckedOffers() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.primaryCTA(checkedCount: 3), "Add 3 & send")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.primaryCTA(checkedCount: 0), "Send")
    }

    func testSendAsIsLabel() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.sendAsIsCTA, "Send as-is — no changes")
    }

    func testOfferTitlesAreShortenedPelotonStyle() {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.offerTitle(for: .sessionWarmup, target: .garmin),
            "Mobility prep"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.offerTitle(for: .exerciseWarmupSets, target: .garmin),
            "Warm-up sets"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.offerTitle(for: .betweenSetRest, target: .garmin),
            "Rest between sets"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.offerTitle(for: .betweenSetRest, target: .apple),
            "Rest between sets"
        )
    }

    func testDeviceNameMatchesTarget() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.deviceName(for: .garmin), "Garmin")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.deviceName(for: .apple), "Apple Watch")
    }

    func testRestOpenSegmentLabelMatchesTarget() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.restOpenSegmentLabel(target: .apple), "Open rest")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.restOpenSegmentLabel(target: .garmin), "Lap button")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.restTimedSegmentLabel, "Timed")
    }

    // MARK: - AMA-2371 review fix: persisted restSec must not bypass 15...300

    func testNormalizedRestSecClampsPersistedValueAboveNewRange() {
        // A standing pref saved under the old 15...600 stepper (e.g. 600)
        // must not render/confirm out-of-range once the sheet narrows to 300.
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(600), 300)
    }

    func testNormalizedRestSecClampsBelowRangeToMinimum() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(5), 15)
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(0), 15)
    }

    func testNormalizedRestSecSnapsToFifteenSecondGrid() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(22), 15)
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(23), 30)
    }

    func testNormalizedRestSecPassesThroughInRangeAlignedValue() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(90), 90)
    }

    func testNormalizedRestSecDefaultsToSixtyWhenNil() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(nil), 60)
    }
}

// MARK: - AMA-2378 v2: enhance sheet mono summaries + copy-lock
// (design 2026-08-04 `make-it-watch-ready-v2-design.md` §Surfaces 1–5)

final class WorkoutEnrichmentV2CopyTests: XCTestCase {
    // MARK: Copy-lock — exact strings from the acceptance/validation matrix

    func testSheetIntroV2IsLocked() {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.sheetIntroV2,
            "Tap a row to shape what goes on your watch — your library workout stays as you wrote it."
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.sheetFootnoteV2,
            "Your watch builds the file when you download — these choices don’t change your saved workout."
        )
    }

    func testCopyLockedStringsFromAcceptance() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.openStepperCaption, "NO TARGET — END ON TAP / CROWN")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.warmupPickHint, "NOT EVERY LIFT NEEDS A RAMP")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.noWarmupsYourCall, "NO WARM-UPS — YOUR CALL")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.cooldownHeaderSuffix, "RUNS AFTER THE LAST SET")
    }

    func testLoadsOffRampHonestyNoteIsLocked() {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.loadsOffRampNote,
            "Loads stay off the ramp — the watch shows % notes only."
        )
    }

    func testSequenceHeaderSuffixesPerKind() {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.sequenceHeaderSuffix(for: .mobility),
            "RUNS BEFORE THE FIRST LIFT"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.sequenceHeaderSuffix(for: .cooldown),
            "RUNS AFTER THE LAST SET"
        )
    }

    // MARK: One-activity goal formatting

    func testFormatMinSecPadsSeconds() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.formatMinSec(120), "2:00")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.formatMinSec(65), "1:05")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.formatMinSec(0), "0:00")
    }

    func testActivityGoalLabelPerKind() throws {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.activityGoalLabel(goal: try ActivityGoal(kind: .time, value: 120), durationSec: nil),
            "2:00"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.activityGoalLabel(goal: try ActivityGoal(kind: .distance, value: 500), durationSec: nil),
            "500 M"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.activityGoalLabel(goal: try ActivityGoal(kind: .cals, value: 15), durationSec: nil),
            "15 CAL"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.activityGoalLabel(goal: try ActivityGoal(kind: .open, value: nil), durationSec: nil),
            "OPEN"
        )
    }

    func testActivityGoalLabelFallsBackToDurationSecWhenGoalAbsent() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.activityGoalLabel(goal: nil, durationSec: 300), "5:00")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.activityGoalLabel(goal: nil, durationSec: nil), "OPEN")
    }

    func testActivitySummaryLabelUppercasesName() throws {
        let goal = try ActivityGoal(kind: .distance, value: 500)
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.activitySummaryLabel(name: "Ski erg", goal: goal, durationSec: nil),
            "SKI ERG 500 M"
        )
    }

    // MARK: Duration estimate math

    func testDurationEstimateSecondsPerKind() throws {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.durationEstimateSeconds(goal: try ActivityGoal(kind: .time, value: 120), durationSec: nil),
            120
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.durationEstimateSeconds(goal: try ActivityGoal(kind: .distance, value: 500), durationSec: nil),
            125
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.durationEstimateSeconds(goal: try ActivityGoal(kind: .cals, value: 15), durationSec: nil),
            60
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.durationEstimateSeconds(goal: try ActivityGoal(kind: .open, value: nil), durationSec: nil),
            90
        )
    }

    func testMobilitySequenceDurationEstimateRoundsToFourMinutes() throws {
        // Ski erg 500m (≈125s) + Assault bike 2:00 (120s) = 245s → round(245/60) = 4 min,
        // matching the design rig's `~4 MIN` (not ceil, which would read `~5 MIN`).
        let activities = [
            EnrichmentActivity(name: "Ski erg", goal: try ActivityGoal(kind: .distance, value: 500)),
            EnrichmentActivity(name: "Assault bike", goal: try ActivityGoal(kind: .time, value: 120))
        ]
        XCTAssertEqual(WorkoutEnrichmentPushCopy.sequenceDurationEstimateSeconds(activities), 245)
        XCTAssertEqual(WorkoutEnrichmentPushCopy.sequenceDurationEstimateMinutes(activities), 4)
    }

    func testSequenceHeaderMetaForMobility() throws {
        let activities = [
            EnrichmentActivity(name: "Ski erg", goal: try ActivityGoal(kind: .distance, value: 500)),
            EnrichmentActivity(name: "Assault bike", goal: try ActivityGoal(kind: .time, value: 120))
        ]
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.sequenceHeaderMeta(activities, kind: .mobility),
            "2 STEPS · ~4 MIN · RUNS BEFORE THE FIRST LIFT"
        )
    }

    // MARK: Sequence summaries — AMA-2408 scaling ladder

    func testMobilitySequenceSummaryMatchesDesignExample() throws {
        let activities = [
            EnrichmentActivity(name: "Ski erg", goal: try ActivityGoal(kind: .distance, value: 500)),
            EnrichmentActivity(name: "Assault bike", goal: try ActivityGoal(kind: .time, value: 120))
        ]
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.sequenceSummary(activities),
            "SKI ➜ BIKE · 2 STEPS"
        )
    }

    func testCooldownSequenceSummaryMatchesDesignExample() throws {
        let activities = [
            EnrichmentActivity(name: "Stretch flow", goal: try ActivityGoal(kind: .time, value: 180)),
            EnrichmentActivity(name: "Treadmill", goal: try ActivityGoal(kind: .open, value: nil))
        ]
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.sequenceSummary(
                activities,
                suffix: WorkoutEnrichmentPushCopy.cooldownRowSummarySuffix
            ),
            "STRETCH ➜ TREADMILL · 2 STEPS"
        )
    }

    func testSequenceSummaryEmptyStepsFallback() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.sequenceSummary([]), "NO STEPS ADDED")
    }

    // MARK: Warm-up sets summaries — AMA-2408 scaling ladder

    func testWarmupSetsSummaryMatchesDesignExampleWithSkipAndOpen() throws {
        let deadliftRamp = PerExerciseRamp(
            exerciseRef: "deadlift",
            enabled: true,
            sets: [try RampSet(kind: .reps, value: 8), try RampSet(kind: .reps, value: 5)]
        )
        let overheadPressRamp = PerExerciseRamp(
            exerciseRef: "overhead press",
            enabled: true,
            sets: [try RampSet(kind: .reps, value: 8), try RampSet(kind: .open, value: nil)]
        )
        let legPressRamp = PerExerciseRamp(exerciseRef: "leg press", enabled: false, sets: [])

        let summary = WorkoutEnrichmentPushCopy.warmupSetsSummaryV2([
            (name: "Deadlift", ramp: deadliftRamp),
            (name: "Overhead Press", ramp: overheadPressRamp),
            (name: "Leg Press", ramp: legPressRamp)
        ])

        // Positive ladder — disabled Leg Press is not listed; N=2 of 3.
        XCTAssertEqual(summary, "DEADLIFT + 1 MORE · 2 OF 3")
        XCTAssertFalse(summary.contains("SKIPPED"))
    }

    func testWarmupExerciseTagSkippedWhenRampNilOrEmpty() {
        let nilTag = WorkoutEnrichmentPushCopy.warmupExerciseTag(name: "Leg Press", ramp: nil)
        XCTAssertFalse(nilTag.contains("SKIPPED"))
        XCTAssertTrue(nilTag.contains("STRAIGHT TO WORKING SETS"))
        let emptyRamp = PerExerciseRamp(exerciseRef: "leg press", enabled: true, sets: [])
        let emptyTag = WorkoutEnrichmentPushCopy.warmupExerciseTag(name: "Leg Press", ramp: emptyRamp)
        XCTAssertFalse(emptyTag.contains("SKIPPED"))
    }

    func testPerExerciseRampDigestVariants() throws {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.perExerciseRampDigest(nil), "STRAIGHT TO WORKING SETS")

        let disabled = PerExerciseRamp(exerciseRef: "leg press", enabled: false)
        XCTAssertEqual(WorkoutEnrichmentPushCopy.perExerciseRampDigest(disabled), "STRAIGHT TO WORKING SETS")

        let noSets = PerExerciseRamp(exerciseRef: "deadlift", enabled: true, sets: [])
        XCTAssertEqual(WorkoutEnrichmentPushCopy.perExerciseRampDigest(noSets), "DEFAULT RAMP")

        let ramp = PerExerciseRamp(
            exerciseRef: "deadlift",
            enabled: true,
            sets: [try RampSet(kind: .reps, value: 8), try RampSet(kind: .reps, value: 5)]
        )
        XCTAssertEqual(WorkoutEnrichmentPushCopy.perExerciseRampDigest(ramp), "8 REPS → 5 REPS")

        let withOpen = PerExerciseRamp(
            exerciseRef: "overhead press",
            enabled: true,
            sets: [try RampSet(kind: .reps, value: 8), try RampSet(kind: .open, value: nil)]
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.perExerciseRampDigest(withOpen),
            "8 REPS → OPEN · END ON TAP"
        )
    }

    // MARK: AMA-2378 Task 5 — pick screen + ramp editor header meta

    func testWarmupPickHeaderMetaJoinsCountAndHint() {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.warmupPickHeaderMeta(enabledCount: 1, total: 3),
            "1 OF 3 EXERCISES · NOT EVERY LIFT NEEDS A RAMP"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.warmupPickHeaderMeta(enabledCount: 1, total: 1),
            "1 OF 1 EXERCISE · NOT EVERY LIFT NEEDS A RAMP"
        )
    }

    func testRampEditorHeaderMetaWithKnownWorkingSetCount() {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.rampEditorHeaderMeta(setCount: 2, workingSetCount: 3),
            "2 WARM-UP SETS → THEN YOUR 3 WORKING SETS"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.rampEditorHeaderMeta(setCount: 1, workingSetCount: 1),
            "1 WARM-UP SET → THEN YOUR 1 WORKING SET"
        )
    }

    func testRampEditorHeaderMetaFallsBackWhenWorkingSetCountUnknown() {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.rampEditorHeaderMeta(setCount: 2, workingSetCount: nil),
            "2 WARM-UP SETS → THEN YOUR WORKING SETS"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.rampEditorHeaderMeta(setCount: 0, workingSetCount: 0),
            "0 WARM-UP SETS → THEN YOUR WORKING SETS"
        )
    }
}
