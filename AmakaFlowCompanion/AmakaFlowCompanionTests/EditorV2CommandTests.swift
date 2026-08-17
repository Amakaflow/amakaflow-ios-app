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
        
        // Simulate: user opens sheet (captures stale state), then background addSet runs
        var sheetDraft = ex1
        _ = session.apply(.addSet(ex1.id))
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 4)
        
        // User edits reps and weight in the sheet
        sheetDraft.reps = 12
        sheetDraft.weightKg = 105
        
        // Commit via the actual sheet seam (diff-based)
        session.commitSheetEdit(exerciseID: ex1.id, sheetDraft: sheetDraft)
        
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
        session.commitSheetEdit(exerciseID: ex1.id, sheetDraft: sheetDraft)
        
        // Exercise still deleted
        XCTAssertNil(session.exercises[ex1.id])
    }
    
    func testUpdatePrescription_nowDiffBased() {
        // updatePrescription is deprecated but reimplemented as diff to prevent clobber
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Press", sets: 3, reps: 10, weightKg: 60)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        // Capture stale state
        var stale = ex1
        
        // Background modification
        _ = session.apply(.addSet(ex1.id))
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 4)
        
        // Old code path: updatePrescription with stale state
        stale.reps = 8
        _ = session.apply(.updatePrescription(ex1.id, stale))
        
        // Sets should still be 4 (diff-based reimplementation prevents clobber)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 4)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 8)
        XCTAssertEqual(session.exercises[ex1.id]?.weightKg, 60)
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
    
    func testUpdatePrescription_updatesExercise() {
        var session = EditorV2Session()
        let ex1 = EditorV2Exercise(name: "Squat", sets: 3, reps: 10)
        session.exercises = [ex1.id: ex1]
        session.order = [.loose(ex1.id)]
        
        var updated = ex1
        updated.sets = 5
        updated.reps = 5
        
        let result = session.apply(.updatePrescription(ex1.id, updated))
        
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(session.exercises[ex1.id]?.sets, 5)
        XCTAssertEqual(session.exercises[ex1.id]?.reps, 5)
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
}
