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

    func testTriSetFormatAddsLandInsideBandedGroup() {
        var session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.triset)
        XCTAssertEqual(session.groups["fmt"]?.name, "Tri-set")

        _ = session.addExercise(named: "Pull Ups")
        // Must stay Tri-set while the third move is still being added — not flip to Superset.
        XCTAssertEqual(session.groups["fmt"]?.name, "Tri-set")
        _ = session.addExercise(named: "Single Arm Row")
        XCTAssertEqual(session.groups["fmt"]?.name, "Tri-set")
        _ = session.addExercise(named: "Forearm Twists")

        XCTAssertEqual(session.exercises.count, 3)
        XCTAssertTrue(session.exercises.values.allSatisfy { $0.groupKey == "fmt" })
        XCTAssertEqual(session.groups["fmt"]?.name, "Tri-set")
        XCTAssertEqual(session.runs.count, 1)
        XCTAssertEqual(session.runs.first?.exercises.count, 3)

        let secondKey = session.beginNextSupersetGroup()
        XCTAssertNotEqual(secondKey, "fmt")
        XCTAssertEqual(session.formatGroupKey, secondKey)
        XCTAssertEqual(session.groups[secondKey]?.name, "Tri-set")
        // Empty next group must stay pinned even though runs only show filled groups —
        // canvas draws an insertion slot from formatGroupKey + zero members.
        XCTAssertFalse(session.exercises.values.contains { $0.groupKey == secondKey })
        XCTAssertEqual(session.runs.count, 1)
        _ = session.addExercise(named: "Dumbbell Press")
        XCTAssertEqual(session.groups[secondKey]?.name, "Tri-set")
        _ = session.addExercise(named: "Band Pull Apart")
        _ = session.addExercise(named: "TRX Tricep Extension")
        XCTAssertEqual(session.runs.count, 2)
        XCTAssertEqual(session.groups[secondKey]?.name, "Tri-set")
        XCTAssertEqual(
            Set(session.exercises.values.filter { $0.groupKey == secondKey }.map(\.name)),
            ["Dumbbell Press", "Band Pull Apart", "TRX Tricep Extension"]
        )
    }

    func testDiscardAndRepinSupersetKeepsTriSetMode() {
        var session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.triset)
        _ = session.addExercise(named: "Pull Ups")
        _ = session.addExercise(named: "Single Arm Row")
        _ = session.addExercise(named: "Forearm Twist")
        let secondKey = session.beginNextSupersetGroup()
        _ = session.addExercise(named: "Dumbbell Press")

        let freshKey = session.discardAndRepinSupersetGroup(secondKey)
        XCTAssertNotNil(freshKey)
        XCTAssertNotEqual(freshKey, secondKey)
        XCTAssertEqual(session.formatGroupKey, freshKey)
        XCTAssertEqual(session.groups[freshKey!]?.name, "Tri-set")
        XCTAssertFalse(session.exercises.values.contains { $0.name == "Dumbbell Press" })
        XCTAssertEqual(session.exercises.count, 3)
        XCTAssertTrue(session.exercises.values.allSatisfy { $0.groupKey == "fmt" })

        let next = session.addExercise(named: "Dumbbell Press")
        XCTAssertEqual(next.groupKey, freshKey)
    }

    func testFocusFormatGroupRepinsAdds() {
        var session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.triset)
        _ = session.addExercise(named: "Pull Ups")
        let secondKey = session.beginNextSupersetGroup()
        _ = session.addExercise(named: "Dumbbell Press")
        session.formatGroupKey = nil

        session.focusFormatGroup(secondKey)
        XCTAssertEqual(session.formatGroupKey, secondKey)
        let next = session.addExercise(named: "Band Pull Apart")
        XCTAssertEqual(next.groupKey, secondKey)
    }

    func testStopAfterAnotherTriSetKeepsEmptySlotPinned() {
        var session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.triset)
        _ = session.addExercise(named: "Pull Ups")
        _ = session.addExercise(named: "Single Arm Row")
        _ = session.addExercise(named: "Forearm Twist")
        let nextKey = session.beginNextSupersetGroup()

        // Athlete leaves the add sheet / stops mid-build — empty group must stay pinned
        // so the next reopen doesn't silently fall back to straight-set adds.
        XCTAssertEqual(session.formatGroupKey, nextKey)
        XCTAssertFalse(session.exercises.values.contains { $0.groupKey == nextKey })
        XCTAssertEqual(session.groups[nextKey]?.name, "Tri-set")
        XCTAssertEqual(session.addExercise(named: "Dumbbell Press").groupKey, nextKey)
    }

    func testDiscardMistakenTriSetThenContinueBuilding() {
        var session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.triset)
        _ = session.addExercise(named: "Pull Ups")
        _ = session.addExercise(named: "Single Arm Row")
        _ = session.addExercise(named: "Forearm Twist")
        let badKey = session.beginNextSupersetGroup()
        _ = session.addExercise(named: "Wrong Move")

        let fresh = session.discardAndRepinSupersetGroup(badKey)
        XCTAssertNotNil(fresh)
        XCTAssertFalse(session.exercises.values.contains { $0.name == "Wrong Move" })
        XCTAssertEqual(session.exercises.count, 3)
        XCTAssertEqual(session.formatGroupKey, fresh)
        XCTAssertEqual(session.addExercise(named: "Dumbbell Press").groupKey, fresh)
    }

    // MARK: - Group / ungroup / runs as

    func testUngroupFlattensExercises() {
        var session = EditorV2Session()
        _ = session.startFormat(.circuit)
        _ = session.addExercise(named: "Burpees")
        _ = session.addExercise(named: "Ski")
        XCTAssertEqual(session.exercises.values.filter { $0.groupKey != nil }.count, 2)

        session.ungroup("fmt")
        XCTAssertNil(session.formatGroupKey)
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertTrue(session.exercises.values.allSatisfy { $0.groupKey == nil })
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
        let ex1 = EditorV2Exercise(id: "a", name: "Bench Press", sets: 4, reps: 8)
        let ex2 = EditorV2Exercise(id: "b", name: "Curls", sets: 3, reps: 12)
        let ex3 = EditorV2Exercise(id: "c", name: "Pull Ups", sets: 4, reps: 8)
        var session = EditorV2Session()
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.order = [.loose("a"), .loose("b"), .loose("c")]
        session.pairSuperset(sourceID: "a", targetID: "c")
        let keyA = session.exercises["a"]?.groupKey
        let keyC = session.exercises["c"]?.groupKey
        XCTAssertNotNil(keyA)
        XCTAssertEqual(keyA, keyC, "Both exercises should be in the same group")
        XCTAssertEqual(session.groups[keyA!]?.type, .superset)
        XCTAssertEqual(session.groups[keyA!]?.name, "Superset")
        XCTAssertTrue(session.order.contains(.loose("b")), "Curls should remain loose")
        XCTAssertTrue(session.order.contains(.group(keyA!)), "Superset group should be in order")
    }

    func testPairingThirdExerciseUpgradesGroupToTriSet() throws {
        let ex1 = EditorV2Exercise(id: "pullups", name: "Pull Ups", sets: 3, reps: 8)
        let ex2 = EditorV2Exercise(id: "rows", name: "Single Arm Row", sets: 3, reps: 10)
        let ex3 = EditorV2Exercise(id: "twists", name: "Forearm Twists", sets: 3, reps: 15)
        let ex4 = EditorV2Exercise(id: "press", name: "Dumbbell Press", sets: 3, reps: 10)
        let ex5 = EditorV2Exercise(id: "pullapart", name: "Band Pull Apart", sets: 3, reps: 15)
        let ex6 = EditorV2Exercise(id: "trx", name: "TRX Tricep Extension", sets: 3, reps: 12)
        var session = EditorV2Session()
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3, ex4.id: ex4, ex5.id: ex5, ex6.id: ex6]
        session.order = [.loose("pullups"), .loose("rows"), .loose("twists"), .loose("press"), .loose("pullapart"), .loose("trx")]
        session.pairSuperset(sourceID: "rows", targetID: "pullups")
        let firstKey = try XCTUnwrap(session.exercises.values.first(where: { $0.id == "pullups" })?.groupKey)
        XCTAssertEqual(session.groups[firstKey]?.name, "Superset")

        session.pairSuperset(sourceID: "twists", targetID: "pullups")
        XCTAssertEqual(session.groups[firstKey]?.name, "Tri-set")
        XCTAssertEqual(
            Set(session.exercises.values.filter { $0.groupKey == firstKey }.map(\.name)),
            ["Pull Ups", "Single Arm Row", "Forearm Twists"]
        )

        session.pairSuperset(sourceID: "pullapart", targetID: "press")
        session.pairSuperset(sourceID: "trx", targetID: "press")
        let secondKey = try XCTUnwrap(session.exercises.values.first(where: { $0.id == "press" })?.groupKey)
        XCTAssertNotEqual(firstKey, secondKey)
        XCTAssertEqual(session.groups[secondKey]?.name, "Tri-set")
        XCTAssertEqual(
            Set(session.exercises.values.filter { $0.groupKey == secondKey }.map(\.name)),
            ["Dumbbell Press", "Band Pull Apart", "TRX Tricep Extension"]
        )
    }

    func testRemoveFromSupersetAndReorder() {
        var session = EditorV2Session()
        _ = session.startFormat(.superset)
        let first = session.addExercise(named: "A")
        let second = session.addExercise(named: "B")
        // Force both into same superset key (format chip uses timed path; pin manually)
        session.ungroup("fmt")
        let exA = EditorV2Exercise(id: first.id, name: "A", sets: 3, reps: 10, groupKey: "ss1")
        let exB = EditorV2Exercise(id: second.id, name: "B", sets: 3, reps: 10, groupKey: "ss1")
        let exC = EditorV2Exercise(id: "c", name: "C", sets: 3, reps: 10)
        session.exercises = [exA.id: exA, exB.id: exB, exC.id: exC]
        session.groups["ss1"] = EditorV2Group(id: "ss1", type: .superset, memberIDs: [first.id, second.id])
        session.order = [.group("ss1"), .loose("c")]

        session.removeFromSuperset(first.id)
        XCTAssertNil(session.exercises.values.first(where: { $0.id == first.id })?.groupKey)

        session.moveExercise(from: "c", to: first.id)
    }

    func testReorderClearsSplitGroupKeys() {
        // D2: order is [Row], not flat exercises. Test that moving a loose exercise
        // into a position that would "split" a group causes the group to ungroup.
        let exA = EditorV2Exercise(id: "a", name: "A", sets: 3, reps: 10)
        let exB = EditorV2Exercise(id: "b", name: "B", sets: 3, reps: 10)
        let exC = EditorV2Exercise(id: "c", name: "C", sets: 3, reps: 10)
        var session = EditorV2Session()
        session.exercises = [exA.id: exA, exB.id: exB, exC.id: exC]
        
        // Create a superset of A and B
        session.pairSuperset(sourceID: "b", targetID: "a")
        let key = session.exercises.values.first(where: { $0.id == "a" })?.groupKey
        XCTAssertNotNil(key)
        
        // D2 order has 2 items: group and loose C
        XCTAssertEqual(session.order.count, 2)
        
        // Reorder at order level is valid (move group vs loose)
        // But test the split-detection in normalize: manually corrupt then apply a command
        guard let groupKey = key else { XCTFail(); return }
        
        // Manually split the group in order (this is what a buggy reorder might do)
        session.order = [.loose("a"), .loose("c"), .loose("b")]
        
        // Any command triggers normalize which should detect and fix the split
        _ = session.apply(.addSet("a"))
        
        // After normalize, split groups should be ungrouped
        XCTAssertTrue(session.exercises.values.allSatisfy { $0.groupKey == nil })
        XCTAssertNil(session.groups[groupKey])
    }

    // MARK: - Persistence round-trip

    func testExportBlocksPreserveStructureSource() {
        var session = EditorV2Session(title: "Hyrox Upper")
        let ex1 = EditorV2Exercise(name: "Bench Press", sets: 4, reps: 8, groupKey: "ssA")
        let ex2 = EditorV2Exercise(name: "Pull Ups", sets: 4, reps: 8, groupKey: "ssA")
        let ex3 = EditorV2Exercise(name: "Curls", sets: 3, reps: 12, restSeconds: 60)
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.groups["ssA"] = EditorV2Group(
            id: "ssA",
            type: .superset,
            name: "Superset A",
            config: .init(rounds: 4, restSeconds: 180),
            memberIDs: [ex1.id, ex2.id],
            structureSource: .userConfirmed
        )
        session.order = [.group("ssA"), .loose(ex3.id)]

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
        let ex1 = EditorV2Exercise(name: "Plank", durationSeconds: 45, restSeconds: 15)
        let ex2 = EditorV2Exercise(name: "SkiErg", weightKg: 12.5, restSeconds: 30, calories: 20)
        let ex3 = EditorV2Exercise(name: "Run", distanceMeters: 400, restSeconds: 60)
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.order = [.loose(ex1.id), .loose(ex2.id), .loose(ex3.id)]
        let intervals = session.toSaveIntervals()
        XCTAssertEqual(intervals.count, 3)
        let plank = intervals.first { $0.name == "Plank" }
        let skierg = intervals.first { $0.name == "SkiErg" }
        let run = intervals.first { $0.name == "Run" }
        
        XCTAssertEqual(plank?.type, "time")
        XCTAssertEqual(plank?.seconds, 45)
        XCTAssertEqual(plank?.restSeconds, 15)
        XCTAssertEqual(skierg?.type, "time")
        XCTAssertEqual(skierg?.seconds, 20)
        XCTAssertEqual(skierg?.target, "20 cal")
        XCTAssertEqual(skierg?.restSeconds, 30)
        XCTAssertEqual(skierg?.load, "12.5 kg")
        XCTAssertEqual(run?.type, "distance")
        XCTAssertEqual(run?.meters, 400)
        XCTAssertEqual(run?.restSeconds, 60)
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
        XCTAssertEqual(session.exercises.values.map(\.name).sorted(), [
            "Curl to Press", "Hammer Curl", "Push Up", "Rows"
        ].sorted())

        // Drag Push Up (index 3) to first.
        session.reorder(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        let blocks = session.toSocialImportBlocks()
        let names = blocks.flatMap(\.exercises).map(\.name)
        XCTAssertEqual(names, ["Push Up", "Hammer Curl", "Curl to Press", "Rows"])

        let intervals = session.toSaveIntervals()
        XCTAssertEqual(intervals.map(\.name), ["Push Up", "Hammer Curl", "Curl to Press", "Rows"])
    }

    func testReorderThenReEditKeepsOrder() {
        let ex1 = EditorV2Exercise(id: "1", name: "A", sets: 3, reps: 10)
        let ex2 = EditorV2Exercise(id: "2", name: "B", sets: 3, reps: 10)
        let ex3 = EditorV2Exercise(id: "3", name: "C", sets: 3, reps: 10)
        var session = EditorV2Session()
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.order = [.loose("1"), .loose("2"), .loose("3")]
        session.reorder(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        session.updateExercise("3") { $0.reps = 12 }
        session.addSet(to: "1")

        XCTAssertEqual(session.exercises.values.first(where: { $0.id == "3" })?.reps, 12)
        XCTAssertEqual(session.exercises.values.first(where: { $0.id == "1" })?.sets, 4)

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
        XCTAssertEqual(roundTrip.exercises.values.first(where: { $0.name == "C" })?.reps, 12)
        XCTAssertEqual(roundTrip.exercises.values.first(where: { $0.name == "A" })?.sets, 4)
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
        let row = try XCTUnwrap(session.exercises.values.first)

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

    func testBodyweightAndWeightedLoadAppearInSummaryAndExport() {
        var bodyweight = EditorV2Exercise(name: "Pull Ups", sets: 3, reps: 10, restSeconds: 60)
        bodyweight.setBodyweightLoad()
        XCTAssertEqual(bodyweight.summaryLine, "3 × 10 · bodyweight · 60S REST")
        XCTAssertEqual(bodyweight.exportLoadString, "bodyweight")

        var weighted = EditorV2Exercise(name: "Dumbbell Press", sets: 3, reps: 10, restSeconds: 60)
        weighted.setWeightedLoad(kilograms: 22.5)
        XCTAssertEqual(weighted.summaryLine, "3 × 10 · 22.5 kg · 60S REST")
        XCTAssertEqual(weighted.exportLoadString, "22.5 kg")
        XCTAssertFalse(weighted.isBodyweight)
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
        XCTAssertEqual(exercise.summaryLine, "3 × OPEN · TRANSITION")
    }

    func testRepRangeExportsThroughSocialImportBlocks() {
        let ex = EditorV2Exercise(
            name: "Squat",
            sets: 3,
            repsRange: RepsRange(low: 8, high: 10),
            restSeconds: 60
        )
        var session = EditorV2Session(title: "Range day")
        session.exercises = [ex.id: ex]
        session.order = [.loose(ex.id)]

        let exported = session.toSocialImportBlocks().flatMap(\.exercises).first
        XCTAssertEqual(exported?.repsRange, "8-10")
        XCTAssertNil(exported?.reps)
    }

    func testRepRangeExportsThroughSaveIntervals() {
        let ex = EditorV2Exercise(
            name: "Squat",
            sets: 3,
            repsRange: RepsRange(low: 8, high: 10),
            restSeconds: 60
        )
        var session = EditorV2Session(title: "Range day")
        session.exercises = [ex.id: ex]
        session.order = [.loose(ex.id)]

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
        let ex1 = EditorV2Exercise(name: "SkiErg", sets: 3, calories: 15)
        let ex2 = EditorV2Exercise(name: "Assault Bike", sets: 3, openGoal: true)
        var session = EditorV2Session(title: "Conditioning")
        session.exercises = [ex1.id: ex1, ex2.id: ex2]
        session.order = [.loose(ex1.id), .loose(ex2.id)]

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
                "af_exsheet_target_distance",
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
        let memory = EditorV2EditTargetMemory(exercise: exercise)
        var draft = exercise
        draft.sets = 4

        let committed = editorV2CommitEditDraft(draft, targetMemory: memory)

        XCTAssertEqual(committed.sets, 4)
        XCTAssertEqual(committed.distanceMeters, 400)
        XCTAssertNil(committed.reps)
    }

    /// AMA-2443 slice 5 — Distance is now a TRACK chip, so a distance row opens
    /// on Distance and moving to Reps is a deliberate conversion, not a no-op.
    func testEditSheetSwitchingDistanceRowToRepsConvertsTheTarget() {
        let exercise = EditorV2Exercise(name: "Run", sets: 3, distanceMeters: 400)
        var memory = EditorV2EditTargetMemory(exercise: exercise)
        XCTAssertEqual(memory.kind, .distance)
        memory.select(.reps)

        let committed = editorV2CommitEditDraft(exercise, targetMemory: memory)

        XCTAssertNil(committed.distanceMeters)
        XCTAssertEqual(committed.reps, EditorV2EditTargetMemory.defaultReps)
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
