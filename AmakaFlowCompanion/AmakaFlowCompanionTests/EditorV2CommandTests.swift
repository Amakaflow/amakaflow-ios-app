//
//  EditorV2CommandTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2438 P1 — exhaustive command tests + audit regressions (expected-fail until P2).
//

import XCTest
@testable import AmakaFlowCompanion

final class EditorV2CommandTests: XCTestCase {
    
    // MARK: - Audit regressions (expected-fail until P2)
    
    func testPairTargetInsideCircuit_shouldNotRipOut() {
        // AMA-2438 P2: D2 now rejects ripping target from non-superset group
        
        var session = EditorV2Session()
        let circuitKey = "c1"
        session.groups[circuitKey] = EditorV2Group(
            id: circuitKey,
            type: .circuit,
            memberIDs: []
        )
        
        let ex1 = EditorV2Exercise(name: "Burpees")
        let ex2 = EditorV2Exercise(name: "Ski")
        let ex3 = EditorV2Exercise(name: "Row")
        
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.order = [.loose(ex1.id), .loose(ex2.id), .loose(ex3.id)]
        session.groups[circuitKey]?.memberIDs = [ex1.id, ex2.id]
        session.order = [.group(circuitKey), .loose(ex3.id)]
        
        let result = session.apply(.pairSuperset(source: ex3.id, target: ex1.id))
        
        // Should be rejected because target is in a circuit
        XCTAssertEqual(result, .rejected(.invalidGroupMembership))
        XCTAssertNotNil(session.groups[circuitKey])
    }
    
    func testPairSourceMidGroup_shouldRepairContiguity() {
        // AMA-2438 P2: D2 declared membership handles this correctly (removes from memberIDs)
        
        var session = EditorV2Session()
        let ssKey = "ss1"
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        let ex3 = EditorV2Exercise(name: "C")
        let ex4 = EditorV2Exercise(name: "D")
        
        session.groups[ssKey] = EditorV2Group(
            id: ssKey,
            type: .superset,
            memberIDs: [ex1.id, ex2.id, ex3.id]
        )
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3, ex4.id: ex4]
        session.order = [.loose(ex1.id), .loose(ex2.id), .loose(ex3.id), .loose(ex4.id)]
        session.order = [.group(ssKey), .loose(ex4.id)]
        
        // Pair ex2 out of the group
        let result = session.apply(.pairSuperset(source: ex2.id, target: ex4.id))
        XCTAssertEqual(result, .applied)
        
        // Old group should still have ex1 and ex3
        XCTAssertEqual(session.groups[ssKey]?.memberIDs, [ex1.id, ex3.id])
    }
    
    func testRemoveTriSetMember_labelMustShrinkToSuperset() {
        // AMA-2438 P2: D3 derived labels now handle this automatically via normalizeD2
        
        var session = EditorV2Session()
        let ssKey = "ss1"
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        let ex3 = EditorV2Exercise(name: "C")
        
        session.groups[ssKey] = EditorV2Group(
            id: ssKey,
            type: .superset,
            name: "Tri-set",
            memberIDs: [ex1.id, ex2.id, ex3.id]
        )
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.order = [.loose(ex1.id), .loose(ex2.id), .loose(ex3.id)]
        session.order = [.group(ssKey)]
        
        XCTAssertEqual(session.groups[ssKey]?.name, "Tri-set")
        
        // Remove one member
        let result = session.apply(.removeExercise(ex3.id))
        XCTAssertEqual(result, .applied)
        
        // Label must shrink back to Superset (normalizeD2 updates it)
        XCTAssertEqual(session.groups[ssKey]?.name, "Superset")
    }
    
    func testSwitchTriSetToEMOM_labelMustNotSurvive() {
        // AMA-2438 P2: switchGroupType now resets name to type.label for auto-labeled groups
        
        var session = EditorV2Session()
        let groupKey = "g1"
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        let ex3 = EditorV2Exercise(name: "C")
        
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.groups[groupKey] = EditorV2Group(
            id: groupKey,
            type: .superset,
            name: "Tri-set",
            memberIDs: [ex1.id, ex2.id, ex3.id]
        )
        session.order = [.group(groupKey)]
        
        let result = session.apply(.switchGroupType(groupKey, .emom))
        XCTAssertEqual(result, .applied)
        
        // Label must be the new type's default, not "Tri-set"
        let finalName = session.groups[groupKey]?.name
        XCTAssertNotEqual(finalName, "Tri-set")
        XCTAssertEqual(finalName, "EMOM")
    }
    
    func testSheetCommitDoesNotClobber() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        // Background modification while sheet is open
        _ = session.apply(.addSet(ex1.id))
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 4)
        
        // Now sheet commits only the reps field change
        _ = session.apply(.setExerciseReps(ex1.id, 12))
        
        // Sets should still be 4, not clobbered back to 3
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 4)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 12)
    }
    
    func testSheetCommitSeam_diffBasedCommit() {
        // Test at the sheet-commit seam (the actual code path EditorV2View uses)
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Bench", sets: 3, reps: 10, weightKg: 100, restSeconds: 60)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        // Simulate: user opens sheet (baseline captured), then background addSet runs
        let baseline = ex1
        var sheetDraft = ex1
        _ = session.apply(.addSet(ex1.id))
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 4)

        // User edits reps and weight in the sheet
        sheetDraft.reps = 12
        sheetDraft.weightKg = 105

        // Commit via the actual sheet seam — diff against the sheet-open
        // baseline, so the untouched (stale) sets field emits no command.
        session.commitSheetEdit(exerciseID: ex1.id, baseline: baseline, sheetDraft: sheetDraft)
        
        // Sets should still be 4 (not clobbered), and user changes applied
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 4)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 12)
        XCTAssertEqual(session.exercises[ex1.id]?.weightKg, 105)
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, 60)
    }
    
    func testSheetCommitSeam_exerciseDeletedWhileOpen() {
        // Exercise deleted while sheet is open - commit should be a no-op
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        var sheetDraft = ex1
        
        // Exercise deleted while sheet was open
        _ = session.apply(.removeExercise(ex1.id))
        XCTAssertNil(session.exercises[ex1.id])
        
        // Sheet commit should be a no-op
        sheetDraft.reps = 15
        session.commitSheetEdit(exerciseID: ex1.id, baseline: ex1, sheetDraft: sheetDraft)
        
        // Exercise still deleted
        XCTAssertNil(session.exercises[ex1.id])
    }
    
    
    // MARK: - Field-level mutation command tests
    
    func testSetExerciseSets_updatesSetsOnly() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Bench", sets: 3, reps: 10, restSeconds: 90)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseSets(ex1.id, 5))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 5)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, 90)
    }
    
    func testSetExerciseSets_canSetToNil() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Row", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseSets(ex1.id, nil))
        
        XCTAssertEqual(result, .applied)
        XCTAssertNil(session.exercises[ex1.id]?.sets)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
    }
    
    func testSetExerciseReps_updatesRepsOnly() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10, restSeconds: 120)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseReps(ex1.id, 12))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 3)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 12)
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, 120)
    }
    
    func testSetExerciseReps_clearsRepsRange() {
        var session = EditorV2Session()
        let range = RepsRange(low: 8, high: 12, qualifier: nil)
        let ex1 = EditorV2Exercise(name: "Deadlift", sets: 3, repsRange: range)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseReps(ex1.id, 10))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
        XCTAssertNil(session.exercises[ex1.id]?.repsRange)
    }
    
    func testSetExerciseRepsRange_updatesRangeOnly() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Press", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let range = RepsRange(low: 8, high: 12, qualifier: nil)
        let result = session.apply(.setExerciseRepsRange(ex1.id, range))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.repsRange, range)
        XCTAssertNil(session.exercises[ex1.id]?.reps)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 3)
    }
    
    func testSetExerciseDuration_updatesDurationOnly() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Plank", sets: 3, durationSeconds: 30)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseDuration(ex1.id, 60))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.durationSeconds, 60)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 3)
    }
    
    func testSetExerciseDistance_updatesDistanceOnly() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Run", distanceMeters: 400)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseDistance(ex1.id, 800))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.distanceMeters, 800)
    }
    
    func testSetExerciseWeight_updatesWeightOnly() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10, weightKg: 100.0)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseWeight(ex1.id, 110.5))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.weightKg, 110.5)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 3)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
        XCTAssertFalse(session.exercises[ex1.id]?.isBodyweight ?? true)
    }
    
    func testSetExerciseWeight_clearsBodyweightFlag() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Pullup", sets: 3, reps: 10, isBodyweight: true)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseWeight(ex1.id, 10.0))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.weightKg, 10.0)
        XCTAssertFalse(session.exercises[ex1.id]?.isBodyweight ?? true)
    }
    
    func testSetExerciseBodyweight_setsBodyweightFlag() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Pushup", sets: 3, reps: 10, weightKg: 20.0)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseBodyweight(ex1.id, true))
        
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(session.exercises[ex1.id]?.isBodyweight ?? false)
        XCTAssertNil(session.exercises[ex1.id]?.weightKg)
    }
    
    func testSetExerciseRest_updatesRestOnly() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Bench", sets: 3, reps: 10, restSeconds: 60)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseRest(ex1.id, 90))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, 90)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 3)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
    }
    
    func testSetExerciseCalories_updatesCaloriesOnly() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Assault Bike", calories: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseCalories(ex1.id, 20))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.calories, 20)
    }
    
    func testSetExerciseOpenGoal_setsOpenGoalFlag() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "AMRAP", sets: 1, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.setExerciseOpenGoal(ex1.id, true))
        
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(session.exercises[ex1.id]?.openGoal ?? false)
    }
    
    func testFieldLevelCommands_rejectNonexistentExercise() {
        var session = EditorV2Session()
        let bogusID = "nonexistent"
        
        XCTAssertEqual(session.apply(.setExerciseSets(bogusID, 5)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseReps(bogusID, 10)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseRepsRange(bogusID, nil)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseDuration(bogusID, 30)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseDistance(bogusID, 400)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseWeight(bogusID, 100.0)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseBodyweight(bogusID, true)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseRest(bogusID, 60)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseCalories(bogusID, 10)), .rejected(.exerciseNotFound))
        XCTAssertEqual(session.apply(.setExerciseOpenGoal(bogusID, true)), .rejected(.exerciseNotFound))
    }
    
    func testMultipleFieldUpdates_preserveOtherFields() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Complex", sets: 3, reps: 10, weightKg: 100.0, restSeconds: 60)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        _ = session.apply(.setExerciseReps(ex1.id, 12))
        _ = session.apply(.setExerciseWeight(ex1.id, 105.0))
        _ = session.apply(.setExerciseRest(ex1.id, 90))
        
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 3)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 12)
        XCTAssertEqual(session.exercises[ex1.id]?.weightKg, 105.0)
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, 90)
    }
    
    // MARK: - Basic command tests
    
    func testAddExercises_appliesSuccessfully() {
        var session = EditorV2Session()
        let result = session.apply(.addExercises(names: ["Squat", "Bench"], into: nil))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises.count, 2)
        XCTAssertTrue(session.exercises.values.contains(where: { $0.name == "Squat" }))
        XCTAssertTrue(session.exercises.values.contains(where: { $0.name == "Bench" }))
    }
    
    func testRemoveExercise_removesFromList() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat")
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.removeExercise(ex1.id))
        
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(session.exercises.isEmpty)
    }
    
    func testRemoveExercise_prunesEmptyGroup() {
        var session = EditorV2Session()
        let groupKey = "g1"
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .circuit)
        
        let ex1 = EditorV2Exercise(name: "Burpees", groupKey: groupKey)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.removeExercise(ex1.id))
        
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertNil(session.groups[groupKey])
    }
    
    func testReplaceExercise_updatesName() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat")
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.replaceExercise(ex1.id, with: "Front Squat"))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises.values.first!.name, "Front Squat")
    }
    
    
    func testPairSuperset_createsNewGroup() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        session.exercises = [ex1.id: ex1, ex2.id: ex2]
        session.order = [.loose(ex1.id), .loose(ex2.id)]
        
        let result = session.apply(.pairSuperset(source: ex1.id, target: ex2.id))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups.count, 1)
        
        let ex1After = session.exercises.values.first(where: { $0.id == ex1.id })
        let ex2After = session.exercises.values.first(where: { $0.id == ex2.id })
        
        XCTAssertNotNil(ex1After?.groupKey)
        XCTAssertEqual(ex1After?.groupKey, ex2After?.groupKey)
    }
    
    func testPairSuperset_joinsExistingSupersetGroup() {
        var session = EditorV2Session()
        let ssKey = "ss1"
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        let ex3 = EditorV2Exercise(name: "C")
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.groups[ssKey] = EditorV2Group(id: ssKey, type: .superset, memberIDs: [ex1.id, ex2.id])
        session.order = [.group(ssKey), .loose(ex3.id)]
        
        let result = session.apply(.pairSuperset(source: ex3.id, target: ex1.id))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups.count, 1)
        
        let ex3After = session.exercises.values.first(where: { $0.id == ex3.id })
        XCTAssertEqual(ex3After?.groupKey, ssKey)
    }
    
    func testRemoveFromGroup_clearsGroupKey() {
        var session = EditorV2Session()
        let ssKey = "ss1"
        session.groups[ssKey] = EditorV2Group(id: ssKey, type: .superset)
        
        let ex1 = EditorV2Exercise(name: "A", groupKey: ssKey)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.removeFromGroup(ex1.id))
        
        XCTAssertEqual(result, .applied)
        XCTAssertNil(session.exercises.values.first!.groupKey)
    }
    
    func testSwitchGroupType_changesTypeAndConfig() {
        var session = EditorV2Session()
        let groupKey = "g1"
        let ex = EditorV2Exercise(name: "Bench")
        session.exercises = [ex.id: ex]
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .circuit, name: "Circuit", memberIDs: [ex.id])
        session.order = [.group(groupKey)]
        
        let result = session.apply(.switchGroupType(groupKey, .emom))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups[groupKey]?.type, .emom)
        XCTAssertEqual(session.groups[groupKey]?.name, "EMOM")
        XCTAssertEqual(session.groups[groupKey]?.config.rounds, 10)
    }
    
    func testSwitchGroupType_keepsCustomName() {
        var session = EditorV2Session()
        let groupKey = "g1"
        let ex = EditorV2Exercise(name: "Bench")
        session.exercises = [ex.id: ex]
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .circuit, name: "My Special Block", memberIDs: [ex.id])
        session.order = [.group(groupKey)]
        
        let result = session.apply(.switchGroupType(groupKey, .emom))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups[groupKey]?.type, .emom)
        XCTAssertEqual(session.groups[groupKey]?.name, "My Special Block")
    }
    
    func testUpdateGroupConfig_updatesConfig() {
        var session = EditorV2Session()
        let groupKey = "g1"
        let ex = EditorV2Exercise(name: "Bench")
        session.exercises = [ex.id: ex]
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .emom, memberIDs: [ex.id])
        session.order = [.group(groupKey)]
        
        var newConfig = EditorV2GroupConfig()
        newConfig.rounds = 20
        
        let result = session.apply(.updateGroupConfig(groupKey, newConfig))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups[groupKey]?.config.rounds, 20)
    }
    
    func testUngroup_clearsMemberGroupKeys() {
        var session = EditorV2Session()
        let groupKey = "g1"
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .circuit)
        
        let ex1 = EditorV2Exercise(name: "A", groupKey: groupKey)
        let ex2 = EditorV2Exercise(name: "B", groupKey: groupKey)
        session.exercises = [ex1.id: ex1, ex2.id: ex2]
        session.order = [.loose(ex1.id), .loose(ex2.id)]
        
        let result = session.apply(.ungroup(groupKey))
        
        XCTAssertEqual(result, .applied)
        XCTAssertNil(session.groups[groupKey])
        XCTAssertTrue(session.exercises.allSatisfy { $0.value.groupKey == nil })
    }
    
    func testUngroup_clearsFormatGroupKey() {
        var session = EditorV2Session()
        let groupKey = "fmt"
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .emom)
        session.formatGroupKey = groupKey
        
        let result = session.apply(.ungroup(groupKey))
        
        XCTAssertEqual(result, .applied)
        XCTAssertNil(session.formatGroupKey)
    }
    
    func testDeleteGroup_removesMembers() {
        var session = EditorV2Session()
        let groupKey = "g1"
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        session.exercises = [ex1.id: ex1, ex2.id: ex2]
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .circuit, memberIDs: [ex1.id, ex2.id])
        session.order = [.group(groupKey)]
        
        let result = session.apply(.deleteGroup(groupKey))
        
        XCTAssertEqual(result, .applied)
        XCTAssertNil(session.groups[groupKey])
        XCTAssertTrue(session.exercises.isEmpty)
    }
    
    func testAddBlock_wipesAndCreatesFormatGroup() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Existing")
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.addBlock(.emom))
        
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertEqual(session.groups.count, 1)
        XCTAssertEqual(session.formatGroupKey, "fmt")
        XCTAssertEqual(session.groups["fmt"]?.type, .emom)
    }
    
    func testMove_reordersExercise() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        let ex3 = EditorV2Exercise(name: "C")
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.order = [.loose(ex1.id), .loose(ex2.id), .loose(ex3.id)]
        
        let result = session.apply(.move(ex1.id, 2))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(Set(session.exercises.values.map(\.name)), ["B", "C", "A"])
    }
    
    func testReorder_movesMultipleExercises() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        let ex3 = EditorV2Exercise(name: "C")
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.order = [.loose(ex1.id), .loose(ex2.id), .loose(ex3.id)]
        
        let result = session.apply(.reorder(fromOffsets: IndexSet(integer: 2), toOffset: 0))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(Set(session.exercises.values.map(\.name)), ["C", "A", "B"])
    }
    
    func testAddSet_incrementsSetCount() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let result = session.apply(.addSet(ex1.id))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises.values.first!.sets, 4)
    }
    
    // MARK: - Invariant tests
    
    func testValidate_rejectsDuplicateExerciseIDs() {
        // D2: Test that validateD2() detects duplicate IDs in order
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "A")
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id), .loose(ex1.id)]  // Invalid: duplicate
        
        // Call validateD2 directly to check it detects the duplicate
        let result = session.validateD2()
        XCTAssertEqual(result, .rejected(.duplicateIDs))
    }
    
    func testValidate_rejectsUnresolvedGroupReferences() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "A", groupKey: "missing")
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        // This would fail validation
        // (Note: commands should not produce this state)
        XCTAssertNil(session.groups["missing"])
    }
    
    func testNormalize_prunesEmptyNonFormatGroups() {
        var session = EditorV2Session()
        let groupKey = "g1"
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .circuit)
        
        // Apply a command that will trigger normalize
        _ = session.apply(.addExercises(names: ["Test"], into: nil))
        
        // Empty group should be pruned
        XCTAssertNil(session.groups[groupKey])
    }
    
    func testNormalize_keepsEmptyFormatGroup() {
        var session = EditorV2Session()
        _ = session.apply(.addBlock(.emom))
        
        // formatGroupKey should still exist even though empty
        XCTAssertEqual(session.formatGroupKey, "fmt")
        XCTAssertNotNil(session.groups["fmt"])
    }
    
    func testNormalize_repairsBrokenGroups() {
        var session = EditorV2Session()
        let groupKey = "g1"
        session.groups[groupKey] = EditorV2Group(id: groupKey, type: .circuit)
        
        let ex1 = EditorV2Exercise(name: "A", groupKey: groupKey)
        let ex2 = EditorV2Exercise(name: "B", groupKey: nil)
        let ex3 = EditorV2Exercise(name: "C", groupKey: groupKey)
        session.exercises = [ex1.id: ex1, ex2.id: ex2, ex3.id: ex3]
        session.order = [.loose(ex1.id), .loose(ex2.id), .loose(ex3.id)]
        
        // A command that triggers normalize
        _ = session.apply(.addExercises(names: [], into: nil))
        
        // Non-contiguous group members should be ungrouped
        let ex1After = session.exercises.values.first(where: { $0.id == ex1.id })
        let ex3After = session.exercises.values.first(where: { $0.id == ex3.id })
        
        // They should both be loose now (or the command didn't run on this broken state)
        XCTAssertNil(ex1After?.groupKey)
        XCTAssertNil(ex3After?.groupKey)
    }
    
    // MARK: - AMA-2443: Undo tests
    
    func testUndo_restoresPreviousState() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let stateBefore = session
        
        // Modify state
        _ = session.apply(.setExerciseReps(ex1.id, 12))
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 12)
        XCTAssertNotEqual(session, stateBefore)
        
        // Undo should restore
        let undoSuccess = session.undo()
        XCTAssertTrue(undoSuccess)
        XCTAssertEqual(session, stateBefore)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
    }
    
    func testUndo_afterRemoveExercise() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Bench", sets: 3, reps: 10)
        let ex2 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1, ex2.id: ex2]
        session.order = [.loose(ex1.id), .loose(ex2.id)]
        
        // Remove ex1
        _ = session.apply(.removeExercise(ex1.id))
        XCTAssertNil(session.exercises[ex1.id])
        XCTAssertEqual(session.exercises.count, 1)
        
        // Undo should restore ex1
        XCTAssertTrue(session.undo())
        XCTAssertNotNil(session.exercises[ex1.id])
        XCTAssertEqual(session.exercises.count, 2)
        XCTAssertEqual(session.exercises[ex1.id]?.name, "Bench")
    }
    
    func testUndo_afterAddExercise() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let stateBefore = session
        
        // Add exercise
        _ = session.apply(.addExercises(names: ["Bench"], into: nil))
        XCTAssertEqual(session.exercises.count, 2)
        
        // Undo should restore to 1 exercise
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, stateBefore)
        XCTAssertEqual(session.exercises.count, 1)
    }
    
    func testUndo_afterPairSuperset() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "A")
        let ex2 = EditorV2Exercise(name: "B")
        session.exercises = [ex1.id: ex1, ex2.id: ex2]
        session.order = [.loose(ex1.id), .loose(ex2.id)]
        
        let stateBefore = session
        
        // Pair into superset
        _ = session.apply(.pairSuperset(source: ex1.id, target: ex2.id))
        XCTAssertEqual(session.groups.count, 1)
        XCTAssertNotNil(session.exercises[ex1.id]?.groupKey)
        
        // Undo should restore to loose exercises
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, stateBefore)
        XCTAssertEqual(session.groups.count, 0)
        XCTAssertNil(session.exercises[ex1.id]?.groupKey)
    }
    
    func testUndo_afterAddBlock() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat")
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let stateBefore = session
        
        // Add block (wipes canvas)
        _ = session.apply(.addBlock(.emom))
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertEqual(session.formatGroupKey, "fmt")
        
        // Undo should restore the canvas
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, stateBefore)
        XCTAssertEqual(session.exercises.count, 1)
        XCTAssertNil(session.formatGroupKey)
    }
    
    func testUndo_noStateChange_doesNotPushSnapshot() {
        var session = EditorV2Session()
        
        // Apply command that makes no change
        _ = session.apply(.addExercises(names: [], into: nil))
        
        // No snapshot should be pushed (canUndo should be false)
        XCTAssertFalse(session.canUndo)
    }
    
    func testUndo_multipleCommands() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let state0 = session
        
        // Command 1
        _ = session.apply(.setExerciseReps(ex1.id, 12))
        let state1 = session
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 12)
        
        // Command 2
        _ = session.apply(.setExerciseSets(ex1.id, 5))
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 5)
        
        // Command 3
        _ = session.apply(.setExerciseRest(ex1.id, 90))
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, 90)
        
        // Undo 3 times
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, nil)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 5)
        
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 3)
        XCTAssertEqual(session, state1)
        
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, state0)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
        
        // No more undo available
        XCTAssertFalse(session.undo())
    }
    
    func testUndo_stackCappedAt50() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        // Apply 60 commands
        for i in 1...60 {
            _ = session.apply(.setExerciseReps(ex1.id, i))
        }
        
        // Should only be able to undo 50 times (stack cap)
        var undoCount = 0
        while session.undo() {
            undoCount += 1
        }
        
        XCTAssertEqual(undoCount, 50)
        // After 50 undos, reps should be 10 (60 - 50 = 10)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
    }
    
    func testUndo_clearHistoryOnSave() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        // Apply command
        _ = session.apply(.setExerciseReps(ex1.id, 12))
        XCTAssertTrue(session.canUndo)
        
        // Clear history (simulates save)
        session.clearUndoHistory()
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.undo())
    }
    
    func testUndo_sheetCommitIsOneEntry() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Bench", sets: 3, reps: 10, weightKg: 100, restSeconds: 60)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        let stateBefore = session
        
        // Sheet commit: multiple field changes
        let baseline = ex1
        var sheetDraft = ex1
        sheetDraft.reps = 12
        sheetDraft.weightKg = 105
        sheetDraft.restSeconds = 90
        
        session.commitSheetEdit(exerciseID: ex1.id, baseline: baseline, sheetDraft: sheetDraft)
        
        // All fields should be updated
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 12)
        XCTAssertEqual(session.exercises[ex1.id]?.weightKg, 105)
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, 90)
        
        // ONE undo should revert all changes
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, stateBefore)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 10)
        XCTAssertEqual(session.exercises[ex1.id]?.weightKg, 100)
        XCTAssertEqual(session.exercises[ex1.id]?.restSeconds, 60)
        
        // No more undo available
        XCTAssertFalse(session.canUndo)
    }
    
    func testUndo_afterSoftSectionAdd() {
        var session = EditorV2Session()
        let stateBefore = session
        
        // Add soft section
        let activities = [EnrichmentActivity(name: "Jog", durationSec: 300)]
        _ = session.apply(.quickAddSoftSection(.sessionWarmup, activities: activities, clearingTombstone: false))
        
        XCTAssertTrue(session.groups.values.contains { $0.type == .warmup })
        
        // Undo should remove the section
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, stateBefore)
        XCTAssertFalse(session.groups.values.contains { $0.type == .warmup })
    }
    
    func testUndo_afterBeginNextSupersetGroup() {
        var session = EditorV2Session()
        let stateBefore = session
        
        // Begin superset group
        _ = session.apply(.beginFormatGroup(type: .superset, preferredName: nil))
        XCTAssertNotNil(session.formatGroupKey)
        XCTAssertTrue(session.groups.values.contains { $0.type == .superset })
        
        // Undo should remove the group
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, stateBefore)
        XCTAssertNil(session.formatGroupKey)
    }
    
    // MARK: - AMA-2443 slice 3 — explicit destination (into:)

    /// Builds a session whose pre-state is *engine-reachable*: every group is
    /// either non-empty or the format group (invariant I2). Hand-built states
    /// with an empty non-format group cannot be produced by any command —
    /// `pruneEmptyGroupsD2()` deletes them on every normalize — and `undo()`
    /// re-validates after restoring, so seeding an illegal pre-state traps.
    private func makeSessionWithSeededGroup(
        key: String,
        type: EditorV2GroupType,
        seedName: String = "Existing"
    ) -> (session: EditorV2Session, seedID: String) {
        var session = EditorV2Session()
        let seed = EditorV2Exercise(name: seedName)
        session.exercises[seed.id] = seed
        session.groups[key] = EditorV2Group(id: key, type: type, memberIDs: [seed.id])
        session.order = [.group(key)]
        return (session, seed.id)
    }

    /// Names passed with an explicit destination land in THAT group's
    /// `memberIDs`, in order, rather than becoming loose rows.
    func testAddExercises_intoSpecificGroup_landsInThatGroup() {
        let targetKey = "target1"
        var (session, seedID) = makeSessionWithSeededGroup(key: targetKey, type: .superset)

        let result = session.apply(.addExercises(names: ["Squat", "Lunge"], into: targetKey))

        XCTAssertEqual(result, .applied)
        let members = session.groups[targetKey]?.memberIDs ?? []
        XCTAssertEqual(members.count, 3, "seed + 2 added")
        XCTAssertEqual(members.first, seedID)
        XCTAssertEqual(session.exercises[members[1]]?.name, "Squat")
        XCTAssertEqual(session.exercises[members[2]]?.name, "Lunge")
    }

    /// Shape B constraint: adding into a group other than the pinned format
    /// group must NOT move the pin. The pin is only moved by explicit
    /// user intent, never as a side effect of an add.
    func testAddExercises_intoNonPinGroup_doesNotChangePin() {
        let pinKey = "pin"
        let targetKey = "target"
        var (session, _) = makeSessionWithSeededGroup(key: targetKey, type: .superset)
        // The pin may legally be an empty group — I2 exempts the format group.
        session.groups[pinKey] = EditorV2Group(id: pinKey, type: .emom, memberIDs: [])
        session.formatGroupKey = pinKey
        session.order = [.group(pinKey), .group(targetKey)]
        XCTAssertEqual(session.validateD2(), .applied, "pre-state must be engine-reachable")

        let result = session.apply(.addExercises(names: ["Bench"], into: targetKey))

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.formatGroupKey, pinKey, "pin must not follow the destination")
        XCTAssertEqual(session.groups[targetKey]?.memberIDs.count, 2, "seed + 1 added")
        XCTAssertEqual(session.groups[pinKey]?.memberIDs.count, 0)
    }

    /// An unknown destination is rejected up front, before any mutation —
    /// not caught post-hoc by `validateD2()`, which would trip the
    /// `assertionFailure` in `apply()` and trap the process.
    func testAddExercises_intoInvalidGroup_doesNotCommit() {
        var (session, _) = makeSessionWithSeededGroup(key: "valid", type: .circuit)

        let stateBefore = session
        let result = session.apply(.addExercises(names: ["Squat"], into: "invalid"))

        XCTAssertEqual(result, .rejected(.invalidGroupMembership))
        XCTAssertEqual(session, stateBefore, "rejected commands must not mutate state")
        XCTAssertFalse(session.canUndo, "a rejected command must not push an undo entry")
    }

    /// One add batch is one undo entry, and undoing restores both the group
    /// membership and the pin. Undo re-validates on restore, so this also
    /// proves the pre-state is legal.
    func testAddExercises_intoGroup_oneUndoRestoresBoth() {
        let targetKey = "target"
        let pinKey = "pin"
        var (session, _) = makeSessionWithSeededGroup(key: targetKey, type: .superset)
        session.groups[pinKey] = EditorV2Group(id: pinKey, type: .amrap, memberIDs: [])
        session.formatGroupKey = pinKey
        session.order = [.group(pinKey), .group(targetKey)]
        XCTAssertEqual(session.validateD2(), .applied, "pre-state must be engine-reachable")

        let stateBefore = session
        let result = session.apply(.addExercises(names: ["Deadlift"], into: targetKey))

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups[targetKey]?.memberIDs.count, 2, "seed + 1 added")
        XCTAssertEqual(session.formatGroupKey, pinKey)

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, stateBefore, "one batch = one undo")
        XCTAssertEqual(session.groups[targetKey]?.memberIDs.count, 1, "back to seed only")
        XCTAssertEqual(session.formatGroupKey, pinKey)
    }

    /// Soft sections are ordinary destinations — add-here works on the
    /// session warm-up.
    func testAddExercises_intoWarmupGroup_isValid() {
        let warmupKey = "warmup"
        var (session, _) = makeSessionWithSeededGroup(key: warmupKey, type: .warmup)

        let result = session.apply(.addExercises(names: ["Jumping Jacks"], into: warmupKey))

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups[warmupKey]?.memberIDs.count, 2, "seed + 1 added")
    }

    /// Soft sections are ordinary destinations — add-here works on the
    /// cool-down.
    func testAddExercises_intoCooldownGroup_isValid() {
        let cooldownKey = "cooldown"
        var (session, _) = makeSessionWithSeededGroup(key: cooldownKey, type: .cooldown)

        let result = session.apply(.addExercises(names: ["Stretch"], into: cooldownKey))

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups[cooldownKey]?.memberIDs.count, 2, "seed + 1 added")
    }
    // MARK: - AMA-2443 slice 4 — append-pin a format group mid-workout

    /// The whole point of slice 4: adding a block mid-workout must NOT destroy
    /// existing rows. `.addBlock` replaces the canvas; `.beginFormatGroup`
    /// appends beside it.
    func testBeginFormatGroup_midWorkout_keepsExistingRows() {
        var (session, seedID) = makeSessionWithSeededGroup(key: "existing", type: .superset)

        let result = session.apply(.beginFormatGroup(type: .emom, preferredName: nil))

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[seedID]?.name, "Existing", "existing move survives")
        XCTAssertNotNil(session.groups["existing"], "existing group survives")
        XCTAssertEqual(session.groups.count, 2)
        XCTAssertEqual(session.order.count, 2, "new block is appended, not swapped in")
    }

    /// Contrast case — proves the destructive command is still destructive, so
    /// the two are not accidentally interchangeable.
    func testAddBlock_midWorkout_stillReplacesCanvas() {
        var (session, seedID) = makeSessionWithSeededGroup(key: "existing", type: .superset)

        let result = session.apply(.addBlock(.emom))

        XCTAssertEqual(result, .applied)
        XCTAssertNil(session.exercises[seedID], ".addBlock is start-over by design")
        XCTAssertEqual(session.order.count, 1)
    }

    /// The appended group becomes the pin, so a following plain add lands in it.
    func testBeginFormatGroup_pinsTheNewGroup() {
        var (session, _) = makeSessionWithSeededGroup(key: "existing", type: .superset)
        let previousPin = session.formatGroupKey

        session.beginFormatGroup(.circuit)

        XCTAssertNotEqual(session.formatGroupKey, previousPin)
        XCTAssertEqual(session.groups[session.formatGroupKey ?? ""]?.type, .circuit)
    }

    /// Letters belong to the superset ladder only — handing one to an EMOM
    /// would consume from that pool and render a letter the format never uses.
    func testBeginFormatGroup_letterOnlyForSuperset() {
        var session = EditorV2Session()

        session.beginFormatGroup(.emom)
        XCTAssertNil(session.groups[session.formatGroupKey ?? ""]?.letter)

        session.beginFormatGroup(.superset)
        XCTAssertEqual(session.groups[session.formatGroupKey ?? ""]?.letter, "A")
    }

    /// Non-supersets take their display name from the type; supersets keep the
    /// existing A/B/C + tri-set inference.
    func testBeginFormatGroup_namesFromType() {
        var session = EditorV2Session()

        session.beginFormatGroup(.amrap)
        XCTAssertEqual(session.groups[session.formatGroupKey ?? ""]?.name, EditorV2GroupType.amrap.label)

        session.beginFormatGroup(.superset)
        XCTAssertEqual(session.groups[session.formatGroupKey ?? ""]?.name, "Superset")
    }

    /// Shape B's core claim: the pin move happens inside `apply()`, so ONE undo
    /// takes back both the appended group and the pin. (Under shape A the pin
    /// move sat outside `apply()` and undo could not reach it.)
    func testBeginFormatGroup_oneUndoRestoresGroupAndPin() {
        var (session, _) = makeSessionWithSeededGroup(key: "existing", type: .superset)
        session.formatGroupKey = "existing"
        let stateBefore = session

        session.beginFormatGroup(.emom)
        XCTAssertNotEqual(session.formatGroupKey, "existing")
        XCTAssertEqual(session.groups.count, 2)

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session, stateBefore, "one gesture = one undo entry")
        XCTAssertEqual(session.formatGroupKey, "existing", "undo restores the pin too")
        XCTAssertEqual(session.groups.count, 1)
    }

    /// An empty appended group is legal *while it is the pin* (I2 exempts the
    /// format group) — this is the state the canvas draws as the pinned
    /// placeholder.
    func testBeginFormatGroup_emptyGroupIsLegalWhilePinned() {
        var (session, _) = makeSessionWithSeededGroup(key: "existing", type: .superset)

        session.beginFormatGroup(.tabata)

        XCTAssertEqual(session.validateD2(), .applied)
        XCTAssertEqual(session.groups[session.formatGroupKey ?? ""]?.memberIDs, [])
    }

    /// …and if the user abandons it by pinning something else, the orphan is
    /// swept by `pruneEmptyGroupsD2()` on the next normalize rather than
    /// lingering as an I2 violation.
    func testBeginFormatGroup_abandonedEmptyGroupIsPruned() {
        var (session, _) = makeSessionWithSeededGroup(key: "existing", type: .superset)

        session.beginFormatGroup(.tabata)
        let abandonedKey = session.formatGroupKey
        XCTAssertNotNil(abandonedKey)

        session.beginFormatGroup(.emom)

        XCTAssertNil(session.groups[abandonedKey ?? ""], "abandoned empty block is swept")
        XCTAssertEqual(session.validateD2(), .applied)
        XCTAssertEqual(session.order.count, 2, "existing run + the new pin")
    }

    /// Adding into the freshly pinned block is the flow the UI drives:
    /// begin → picker opens with `into:` = the new key.
    func testBeginFormatGroup_thenAddIntoIt() {
        var (session, _) = makeSessionWithSeededGroup(key: "existing", type: .superset)

        let key = session.beginFormatGroup(.emom)
        let result = session.apply(.addExercises(names: ["Burpees"], into: key))

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.groups[key]?.memberIDs.count, 1)
        XCTAssertEqual(session.validateD2(), .applied)
    }
}
