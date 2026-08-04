//
//  EditorV2Tests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2307 — Editor v2 pure logic: group/ungroup, format chips, reorder, row invariant.
//

import XCTest
@testable import AmakaFlowCompanion

final class EditorV2Tests: XCTestCase {

    // MARK: - Summary + controls invariant

    func testExerciseSummaryMatchesHevyMonoFormat() {
        let exercise = EditorV2Exercise(
            name: "Bench Press",
            sets: 4,
            reps: 8,
            weightKg: 60,
            restSeconds: 60
        )
        XCTAssertEqual(exercise.summaryLine, "4 × 8 · 60 kg · 60S REST")
        XCTAssertEqual(EditorV2Exercise.maxVisibleControlsPerRow, 2)
    }

    func testGroupMetaLinesPerType() {
        XCTAssertEqual(
            EditorV2Group(type: .emom, config: .init(rounds: 10)).metaLine,
            "10 MIN · EVERY MINUTE"
        )
        XCTAssertEqual(
            EditorV2Group(type: .superset, config: .init(rounds: 4, restSeconds: 180)).metaLine,
            "4 ROUNDS · 3 MIN REST"
        )
        XCTAssertEqual(
            EditorV2Group(type: .superset, config: .init(rounds: 3, restSeconds: 90)).metaLine,
            "3 ROUNDS · 90S REST"
        )
        XCTAssertEqual(
            EditorV2Group(
                type: .tabata,
                config: .init(rounds: 8, restSeconds: 10, workSeconds: 20)
            ).metaLine,
            "20S ON · 10S OFF · ×8"
        )
    }

    // MARK: - Format-first creation

    func testCreateEmptyNeverRequiresStructure() {
        var session = EditorV2Session(title: "")
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertNil(session.formatGroupKey)
        XCTAssertTrue(session.groups.isEmpty)

        let added = session.addExercise(named: "Goblet squat")
        XCTAssertEqual(added.sets, 3)
        XCTAssertEqual(added.reps, 10)
        XCTAssertEqual(added.restSeconds, 60)
        XCTAssertNil(added.groupKey)
    }

    func testFormatChipPinsGroupAndAddsLandInside() {
        var session = EditorV2Session()
        let key = session.startFormat(.emom)
        XCTAssertEqual(key, "fmt")
        XCTAssertEqual(session.groups[key]?.type, .emom)
        XCTAssertEqual(session.formatGroupKey, key)

        let row = session.addExercise(named: "Cal Row")
        XCTAssertEqual(row.groupKey, key)
        XCTAssertEqual(row.reps, 10)
        XCTAssertNil(row.sets)
        XCTAssertEqual(session.runs.count, 1)
        XCTAssertEqual(session.runs.first?.groupKey, key)
    }

    // MARK: - Group / ungroup / runs as

    func testUngroupFlattensExercises() {
        var session = EditorV2Session()
        _ = session.startFormat(.circuit)
        _ = session.addExercise(named: "Burpees")
        _ = session.addExercise(named: "Ski")
        XCTAssertEqual(session.exercises.filter { $0.groupKey != nil }.count, 2)

        session.ungroup("fmt")
        XCTAssertNil(session.formatGroupKey)
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertTrue(session.exercises.allSatisfy { $0.groupKey == nil })
    }

    func testSwitchRunsAsReplacesConfig() {
        var session = EditorV2Session()
        _ = session.startFormat(.emom)
        session.switchGroupType("fmt", to: .tabata)
        XCTAssertEqual(session.groups["fmt"]?.type, .tabata)
        XCTAssertEqual(session.groups["fmt"]?.config.workSeconds, 20)
        XCTAssertEqual(session.groups["fmt"]?.structureSource, .userConfirmed)
    }

    func testAllRunsAsTypesHaveSteppers() {
        for type in EditorV2GroupType.runsAsOptions {
            let group = EditorV2Group(type: type)
            XCTAssertFalse(group.stepperRows.isEmpty, "\(type) should expose steppers")
        }
    }

    // MARK: - Superset pairing + reorder

    func testPairSupersetJoinsAdjacent() {
        var session = EditorV2Session(exercises: [
            EditorV2Exercise(id: "a", name: "Bench Press", sets: 4, reps: 8),
            EditorV2Exercise(id: "b", name: "Curls", sets: 3, reps: 12),
            EditorV2Exercise(id: "c", name: "Pull Ups", sets: 4, reps: 8)
        ])
        session.pairSuperset(sourceID: "a", targetID: "c")
        XCTAssertEqual(session.exercises.map(\.name), ["Curls", "Pull Ups", "Bench Press"])
        let key = session.exercises.first(where: { $0.id == "c" })?.groupKey
        XCTAssertNotNil(key)
        XCTAssertEqual(session.exercises.first(where: { $0.id == "a" })?.groupKey, key)
        XCTAssertEqual(session.groups[key!]?.type, .superset)
    }

    func testRemoveFromSupersetAndReorder() {
        var session = EditorV2Session()
        _ = session.startFormat(.superset)
        let first = session.addExercise(named: "A")
        let second = session.addExercise(named: "B")
        // Force both into same superset key (format chip uses timed path; pin manually)
        session.ungroup("fmt")
        session.exercises = [
            EditorV2Exercise(id: first.id, name: "A", sets: 3, reps: 10, groupKey: "ss1"),
            EditorV2Exercise(id: second.id, name: "B", sets: 3, reps: 10, groupKey: "ss1"),
            EditorV2Exercise(id: "c", name: "C", sets: 3, reps: 10)
        ]
        session.groups["ss1"] = EditorV2Group(id: "ss1", type: .superset)

        session.removeFromSuperset(first.id)
        XCTAssertNil(session.exercises.first(where: { $0.id == first.id })?.groupKey)

        session.moveExercise(from: "c", to: first.id)
        XCTAssertEqual(session.exercises.map(\.name), ["C", "A", "B"])
    }

    func testReorderClearsSplitGroupKeys() {
        var session = EditorV2Session(exercises: [
            EditorV2Exercise(id: "a", name: "A", sets: 3, reps: 10, groupKey: "ss1"),
            EditorV2Exercise(id: "b", name: "B", sets: 3, reps: 10, groupKey: "ss1"),
            EditorV2Exercise(id: "c", name: "C", sets: 3, reps: 10)
        ])
        session.groups["ss1"] = EditorV2Group(id: "ss1", type: .superset)

        // Move C between A and B → splits the superset.
        session.reorder(fromOffsets: IndexSet(integer: 2), toOffset: 1)
        XCTAssertEqual(session.exercises.map(\.name), ["A", "C", "B"])
        XCTAssertTrue(session.exercises.allSatisfy { $0.groupKey == nil })
        XCTAssertNil(session.groups["ss1"])
    }

    // MARK: - Persistence round-trip

    func testExportBlocksPreserveStructureSource() {
        var session = EditorV2Session(title: "Hyrox Upper")
        session.groups["ssA"] = EditorV2Group(
            id: "ssA",
            type: .superset,
            name: "Superset A",
            config: .init(rounds: 4, restSeconds: 180),
            structureSource: .userConfirmed
        )
        session.exercises = [
            EditorV2Exercise(name: "Bench Press", sets: 4, reps: 8, groupKey: "ssA"),
            EditorV2Exercise(name: "Pull Ups", sets: 4, reps: 8, groupKey: "ssA"),
            EditorV2Exercise(name: "Curls", sets: 3, reps: 12, restSeconds: 60)
        ]

        let blocks = session.toSocialImportBlocks()
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].type, "superset")
        XCTAssertEqual(blocks[0].structureSource, "user_confirmed")
        XCTAssertEqual(blocks[0].restSec, 180)
        XCTAssertEqual(blocks[0].exercises.count, 2)
        XCTAssertEqual(blocks[1].type, "sets")
        XCTAssertEqual(blocks[1].structureSource, "user_confirmed")
        XCTAssertEqual(blocks[1].exercises.first?.name, "Curls")
    }

    func testSeedFromEditBlocksBuildsRuns() {
        let blocks = [
            DDEditorBlockDraft(
                structure: .superset,
                label: "Superset A",
                rounds: 4,
                restBetweenRoundsSeconds: 180,
                exercises: [
                    DDEditorExerciseDraft(name: "Bench Press", sets: 4, reps: 8, weightKg: 60),
                    DDEditorExerciseDraft(name: "Pull Ups", sets: 4, reps: 8)
                ]
            ),
            DDEditorBlockDraft(
                structure: .sets,
                label: "Main",
                exercises: [
                    DDEditorExerciseDraft(name: "Curls", sets: 3, reps: 12, restSeconds: 60)
                ]
            )
        ]
        let session = EditorV2Session.from(title: "Test", blocks: blocks)
        XCTAssertEqual(session.title, "Test")
        XCTAssertEqual(session.runs.count, 2)
        XCTAssertNotNil(session.runs[0].groupKey)
        XCTAssertNil(session.runs[1].groupKey)
        XCTAssertEqual(session.exercises.count, 3)
    }

    func testNewModeSeedIsEmptyWithoutStructureQuestion() {
        let session = EditorV2Session.from(mode: .new, workout: nil)
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertEqual(session.title, "")
    }

    func testSaveIntervalsPreserveTimeAndCalories() {
        var session = EditorV2Session(title: "Mixed")
        session.exercises = [
            EditorV2Exercise(name: "Plank", durationSeconds: 45, restSeconds: 15),
            EditorV2Exercise(name: "SkiErg", weightKg: 12.5, restSeconds: 30, calories: 20),
            EditorV2Exercise(name: "Run", distanceMeters: 400, restSeconds: 60)
        ]
        let intervals = session.toSaveIntervals()
        XCTAssertEqual(intervals[0].type, "time")
        XCTAssertEqual(intervals[0].seconds, 45)
        XCTAssertEqual(intervals[0].restSeconds, 15)
        XCTAssertEqual(intervals[1].type, "time")
        XCTAssertEqual(intervals[1].seconds, 20)
        XCTAssertEqual(intervals[1].target, "20 cal")
        XCTAssertEqual(intervals[1].restSeconds, 30)
        XCTAssertEqual(intervals[1].load, "12.5 kg")
        XCTAssertEqual(intervals[2].type, "distance")
        XCTAssertEqual(intervals[2].meters, 400)
        XCTAssertEqual(intervals[2].restSeconds, 60)
    }

    func testFormatWeightPreservesTenths() {
        XCTAssertEqual(EditorV2Exercise.formatWeight(12.5), "12.5")
        XCTAssertEqual(EditorV2Exercise.formatWeightLoad(12.5), "12.5 kg")
        XCTAssertEqual(EditorV2Exercise.formatWeight(60), "60")
    }

    // MARK: - Reorder → save payload (dogfood regression)

    func testReorderFourFlatExercisesExportsPushUpFirst() {
        // Social-import style: four separate sets blocks → flat editor rows.
        let seed = [
            DDEditorBlockDraft(
                structure: .sets,
                label: "Main",
                exercises: [DDEditorExerciseDraft(name: "Hammer Curl", sets: 1, reps: 5)]
            ),
            DDEditorBlockDraft(
                structure: .sets,
                label: "Block 2",
                exercises: [DDEditorExerciseDraft(name: "Curl to Press", sets: 1, reps: 5)]
            ),
            DDEditorBlockDraft(
                structure: .sets,
                label: "Block 3",
                exercises: [DDEditorExerciseDraft(name: "Rows", sets: 1, reps: 5)]
            ),
            DDEditorBlockDraft(
                structure: .sets,
                label: "Block 4",
                exercises: [DDEditorExerciseDraft(name: "Push Up", sets: 1, reps: 10)]
            )
        ]
        var session = EditorV2Session.from(title: "Quick Upper Body", blocks: seed)
        XCTAssertEqual(session.exercises.map(\.name), [
            "Hammer Curl", "Curl to Press", "Rows", "Push Up"
        ])

        // Drag Push Up (index 3) to first.
        session.reorder(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(session.exercises.map(\.name), [
            "Push Up", "Hammer Curl", "Curl to Press", "Rows"
        ])

        let blocks = session.toSocialImportBlocks()
        let names = blocks.flatMap(\.exercises).map(\.name)
        XCTAssertEqual(names, ["Push Up", "Hammer Curl", "Curl to Press", "Rows"])

        let intervals = session.toSaveIntervals()
        XCTAssertEqual(intervals.map(\.name), ["Push Up", "Hammer Curl", "Curl to Press", "Rows"])
    }

    func testReorderThenReEditKeepsOrder() {
        var session = EditorV2Session(exercises: [
            EditorV2Exercise(id: "1", name: "A", sets: 3, reps: 10),
            EditorV2Exercise(id: "2", name: "B", sets: 3, reps: 10),
            EditorV2Exercise(id: "3", name: "C", sets: 3, reps: 10)
        ])
        session.reorder(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        session.updateExercise("3") { $0.reps = 12 }
        session.addSet(to: "1")

        XCTAssertEqual(session.exercises.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(session.exercises.first?.reps, 12)
        XCTAssertEqual(session.exercises.first(where: { $0.id == "1" })?.sets, 4)

        let roundTrip = EditorV2Session.from(
            title: "RT",
            blocks: session.toSocialImportBlocks().map { block in
                DDEditorBlockDraft(
                    structure: .sets,
                    label: block.label ?? "Main",
                    exercises: block.exercises.map {
                        DDEditorExerciseDraft(name: $0.name, sets: $0.sets, reps: $0.reps)
                    }
                )
            }
        )
        XCTAssertEqual(roundTrip.exercises.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(roundTrip.exercises.first?.reps, 12)
        XCTAssertEqual(roundTrip.exercises.first(where: { $0.name == "A" })?.sets, 4)
    }

    func testAddSetAndRepEditExportToSaveIntervals() {
        var session = EditorV2Session()
        let squat = session.addExercise(named: "Squat")
        _ = session.addExercise(named: "Bench")
        session.addSet(to: squat.id)
        session.addSet(to: squat.id)
        session.updateExercise(squat.id) { $0.reps = 5 }

        let intervals = session.toSaveIntervals()
        XCTAssertEqual(intervals.first?.name, "Squat")
        XCTAssertEqual(intervals.first?.sets, 5) // default 3 + 2 adds
        XCTAssertEqual(intervals.first?.reps, 5)

        let blocks = session.toSocialImportBlocks()
        XCTAssertEqual(blocks.flatMap(\.exercises).first?.sets, 5)
        XCTAssertEqual(blocks.flatMap(\.exercises).first?.reps, 5)
    }

    func testNewWorkoutSessionSaveShapeHasNoStructureRequirement() {
        var session = EditorV2Session.from(mode: .new, workout: nil)
        XCTAssertTrue(session.exercises.isEmpty)
        _ = session.addExercise(named: "Deadlift")
        _ = session.addExercise(named: "Pull Up")

        let blocks = session.toSocialImportBlocks()
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.type, "sets")
        XCTAssertEqual(blocks.first?.exercises.map(\.name), ["Deadlift", "Pull Up"])
        XCTAssertEqual(session.toSaveIntervals().count, 2)
    }

    // MARK: - Rep range seed + summary (AMA-2311 Task 6)

    func testSeedFromWorkoutRepRangePreservesRangeNotPlainReps() throws {
        let workout = Workout(
            id: "wk-range-1",
            name: "Upper",
            sport: .strength,
            duration: 1800,
            blocks: [
                Block(
                    label: "Main",
                    structure: .straight,
                    rounds: 1,
                    exercises: [
                        Exercise(
                            name: "Squat",
                            canonicalName: nil,
                            sets: 3,
                            reps: "8-10",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: 60,
                            distance: nil,
                            notes: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .instagram
        )

        let session = EditorV2Session.from(mode: .edit, workout: workout)
        let row = try XCTUnwrap(session.exercises.first)

        XCTAssertNil(row.reps)
        XCTAssertEqual(row.repsRange, RepsRange(low: 8, high: 10))
        XCTAssertEqual(row.sets, 3)
        XCTAssertEqual(row.restSeconds, 60)
    }

    func testRepRangeSummaryIsNotRestOnly() {
        let exercise = EditorV2Exercise(
            name: "Squat",
            sets: 3,
            repsRange: RepsRange(low: 8, high: 10),
            restSeconds: 60
        )

        XCTAssertEqual(exercise.summaryLine, "3 × 8–10 · 60S REST")
        XCTAssertNotEqual(exercise.summaryLine, "60S REST")
    }

    func testOpenGoalClearsMutuallyExclusiveTargetsAndFormatsOpenRest() {
        var exercise = EditorV2Exercise(
            name: "Assault Bike",
            sets: 3,
            reps: 10,
            repsRange: RepsRange(low: 8, high: 12),
            durationSeconds: 40,
            distanceMeters: 400,
            calories: 15,
            restOpen: true
        )
        exercise.openGoal = true

        XCTAssertTrue(exercise.openGoal)
        XCTAssertNil(exercise.reps)
        XCTAssertNil(exercise.repsRange)
        XCTAssertNil(exercise.durationSeconds)
        XCTAssertNil(exercise.distanceMeters)
        XCTAssertNil(exercise.calories)
        XCTAssertEqual(exercise.summaryLine, "3 × OPEN · OPEN REST")
    }

    func testRepRangeExportsThroughSocialImportBlocks() {
        var session = EditorV2Session(
            title: "Range day",
            exercises: [
                EditorV2Exercise(
                    name: "Squat",
                    sets: 3,
                    repsRange: RepsRange(low: 8, high: 10),
                    restSeconds: 60
                )
            ]
        )

        let exported = session.toSocialImportBlocks().flatMap(\.exercises).first
        XCTAssertEqual(exported?.repsRange, "8-10")
        XCTAssertNil(exported?.reps)
    }

    func testRepRangeExportsThroughSaveIntervals() {
        let session = EditorV2Session(
            title: "Range day",
            exercises: [
                EditorV2Exercise(
                    name: "Squat",
                    sets: 3,
                    repsRange: RepsRange(low: 8, high: 10),
                    restSeconds: 60
                )
            ]
        )

        let interval = session.toSaveIntervals().first
        XCTAssertEqual(interval?.type, "reps")
        XCTAssertEqual(interval?.target, "8-10")
        XCTAssertEqual(interval?.reps, 9)
    }

    // MARK: - AMA-2368 editor rest Open vs Timed

    func testSetRestIntentOpenClearsTimedSeconds() throws {
        var exercise = EditorV2Exercise(
            name: "Triceps Press Downs",
            sets: 2,
            reps: 12,
            restSeconds: 60
        )
        try exercise.setRestIntent(restSeconds: nil, restOpen: true)
        XCTAssertEqual(exercise.restOpen, true)
        XCTAssertNil(exercise.restSeconds)
        XCTAssertEqual(
            exercise.fieldProvenance[WorkoutEnrichmentMutations.restOpenKey],
            .user
        )
        XCTAssertEqual(
            exercise.fieldProvenance[WorkoutEnrichmentMutations.restSecKey],
            .user
        )
    }

    func testSetRestIntentTimedClearsOpenFlag() throws {
        var exercise = EditorV2Exercise(
            name: "Triceps Press Downs",
            sets: 2,
            reps: 12,
            restOpen: true
        )
        try exercise.setRestIntent(restSeconds: 90, restOpen: false)
        XCTAssertEqual(exercise.restOpen, false)
        XCTAssertEqual(exercise.restSeconds, 90)
        XCTAssertEqual(
            exercise.fieldProvenance[WorkoutEnrichmentMutations.restOpenKey],
            .user
        )
        XCTAssertEqual(
            exercise.fieldProvenance[WorkoutEnrichmentMutations.restSecKey],
            .user
        )
    }

    func testOpenRestNormalizesAwayTimedSecondsWithoutStamping() {
        // Mirrors EditorV2EditSheet.committedDraft — clear seconds, keep provenance.
        var exercise = EditorV2Exercise(
            name: "Triceps Press Downs",
            sets: 2,
            reps: 12,
            restSeconds: 60,
            fieldProvenance: [
                WorkoutEnrichmentMutations.restSecKey: ProvSource.enrichmentDefault,
                WorkoutEnrichmentMutations.restOpenKey: ProvSource.enrichmentDefault,
            ],
            restOpen: true
        )
        if exercise.restOpen == true {
            exercise.restSeconds = nil
        }
        XCTAssertEqual(exercise.restOpen, true)
        XCTAssertNil(exercise.restSeconds)
        XCTAssertEqual(
            exercise.fieldProvenance[WorkoutEnrichmentMutations.restOpenKey],
            ProvSource.enrichmentDefault
        )
        XCTAssertEqual(
            exercise.fieldProvenance[WorkoutEnrichmentMutations.restSecKey],
            ProvSource.enrichmentDefault
        )
    }

    func testExportBlocksPersistCaloriesAndOpenGoalWireFields() throws {
        let session = EditorV2Session(
            title: "Conditioning",
            exercises: [
                EditorV2Exercise(name: "SkiErg", sets: 3, calories: 15),
                EditorV2Exercise(name: "Assault Bike", sets: 3, openGoal: true)
            ]
        )

        let exercises = try XCTUnwrap(session.toSocialImportBlocks().first?.exercises)
        XCTAssertEqual(exercises[0].calories, 15)
        XCTAssertNil(exercises[0].notes)
        XCTAssertEqual(exercises[1].openGoal, true)

        let mapped = APIService.mapperBlockObject(
            from: SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    exercises[0],
                    SocialImportExercise(
                        name: exercises[1].name,
                        sets: 3,
                        reps: 10,
                        repsRange: "8-10",
                        seconds: 45,
                        distanceMeters: 400,
                        calories: 15,
                        openGoal: true
                    )
                ]
            )
        )
        let wireExercises = try XCTUnwrap(mapped["exercises"] as? [[String: Any]])

        XCTAssertEqual(wireExercises[0]["calories"] as? Int, 15)
        XCTAssertEqual(wireExercises[0]["sets"] as? Int, 3)
        XCTAssertNil(wireExercises[0]["notes"])
        XCTAssertEqual(wireExercises[1]["goal"] as? [String: String], ["kind": "open"])
        XCTAssertEqual(wireExercises[1]["sets"] as? Int, 3)
        XCTAssertNil(wireExercises[1]["reps"])
        XCTAssertNil(wireExercises[1]["reps_range"])
        XCTAssertNil(wireExercises[1]["duration_sec"])
        XCTAssertNil(wireExercises[1]["distance_m"])
        XCTAssertNil(wireExercises[1]["calories"])
    }

    // MARK: - AMA-2379 target edit sheet

    func testEditSheetTargetMemoryRetainsValuesAcrossKindSwitches() {
        var memory = EditorV2EditTargetMemory(
            exercise: EditorV2Exercise(name: "Bike", sets: 3, reps: 12)
        )
        XCTAssertEqual(memory.kind, .reps)
        XCTAssertEqual(memory.reps, 12)
        XCTAssertEqual(memory.rangeMin, 8)
        XCTAssertEqual(memory.rangeMax, 12)

        memory.kind = .timed
        memory.workSeconds = 70
        memory.kind = .reps
        XCTAssertEqual(memory.reps, 12)
        memory.kind = .timed
        XCTAssertEqual(memory.workSeconds, 70)
    }

    func testEditSheetRangeMemoryClampsBothBounds() {
        var memory = EditorV2EditTargetMemory(
            exercise: EditorV2Exercise(
                name: "Squat",
                repsRange: RepsRange(low: 8, high: 12)
            )
        )

        memory.setRangeMin(20)
        XCTAssertEqual(memory.rangeMin, 12)
        memory.setRangeMax(4)
        XCTAssertEqual(memory.rangeMax, 12)
        memory.setRangeMin(-1)
        XCTAssertEqual(memory.rangeMin, 1)
        memory.setRangeMax(99)
        XCTAssertEqual(memory.rangeMax, 50)
    }

    func testEditSheetTargetAccessibilityIdentifiersAreStable() {
        XCTAssertEqual(
            EditorV2EditTargetKind.allCases.map(\.accessibilityIdentifier),
            [
                "af_exsheet_target_reps",
                "af_exsheet_target_range",
                "af_exsheet_target_timed",
                "af_exsheet_target_cals",
                "af_exsheet_target_open",
            ]
        )
    }

    func testEditSheetOpenCommitClearsAllMetricTargets() {
        var exercise = EditorV2Exercise(
            name: "Assault Bike",
            sets: 3,
            reps: 10,
            repsRange: RepsRange(low: 8, high: 12),
            durationSeconds: 40,
            distanceMeters: 400,
            calories: 15
        )
        var memory = EditorV2EditTargetMemory(exercise: exercise)
        memory.kind = .open
        memory.apply(to: &exercise)

        XCTAssertTrue(exercise.openGoal)
        XCTAssertNil(exercise.reps)
        XCTAssertNil(exercise.repsRange)
        XCTAssertNil(exercise.durationSeconds)
        XCTAssertNil(exercise.distanceMeters)
        XCTAssertNil(exercise.calories)
    }

    func testEditSheetUntouchedDistancePreservesTargetAndProvenance() {
        var exercise = EditorV2Exercise(
            name: "Run",
            sets: 3,
            distanceMeters: 400,
            fieldProvenance: ["distance_meters": .inferred]
        )
        var memory = EditorV2EditTargetMemory(exercise: exercise)
        memory.apply(to: &exercise)

        XCTAssertEqual(exercise.distanceMeters, 400)
        XCTAssertNil(exercise.reps)
        XCTAssertEqual(exercise.fieldProvenance["distance_meters"], .inferred)
        XCTAssertNil(exercise.fieldProvenance["reps"])
    }

    func testEditSheetCommitPreservesDistanceAfterSetsChangeWithoutTargetChange() {
        let exercise = EditorV2Exercise(name: "Run", sets: 3, distanceMeters: 400)
        var memory = EditorV2EditTargetMemory(exercise: exercise)
        memory.select(.reps) // Reps is already displayed for a distance-only row.
        var draft = exercise
        draft.sets = 4

        let committed = editorV2CommitEditDraft(draft, targetMemory: memory)

        XCTAssertEqual(committed.sets, 4)
        XCTAssertEqual(committed.distanceMeters, 400)
        XCTAssertNil(committed.reps)
    }

    func testEditSheetUnchangedTargetDoesNotStampUserProvenance() {
        var exercise = EditorV2Exercise(
            name: "Bench Press",
            sets: 3,
            reps: 10,
            fieldProvenance: ["reps": .inferred]
        )
        var memory = EditorV2EditTargetMemory(exercise: exercise)
        memory.apply(to: &exercise)

        XCTAssertEqual(exercise.reps, 10)
        XCTAssertEqual(exercise.fieldProvenance["reps"], .inferred)
    }
}
