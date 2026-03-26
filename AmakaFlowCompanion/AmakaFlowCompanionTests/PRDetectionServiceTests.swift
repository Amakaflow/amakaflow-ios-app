//
//  PRDetectionServiceTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for PRDetectionService — AMA-1282
//

import XCTest
@testable import AmakaFlowCompanion

final class PRDetectionServiceTests: XCTestCase {

    var service: PRDetectionService!

    override func setUp() {
        super.setUp()
        service = PRDetectionService()
        // Clear stored PRs before each test
        UserDefaults.standard.removeObject(forKey: "amakaflow_personal_records")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "amakaflow_personal_records")
        super.tearDown()
    }

    // MARK: - Empty Cases

    func testDetectPRsReturnsEmptyWhenNoSets() {
        let result = service.detectPRs(from: [], workoutName: "Test")
        XCTAssertFalse(result.hasPRs)
        XCTAssertTrue(result.newPRs.isEmpty)
    }

    // MARK: - Heaviest Weight

    func testDetectsHeaviestWeightPR() {
        let sets = [
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 1, repsCompleted: 5, weightKg: 80.0),
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 2, repsCompleted: 5, weightKg: 85.0),
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 3, repsCompleted: 3, weightKg: 90.0)
        ]

        let result = service.detectPRs(from: sets, workoutName: "Test")

        XCTAssertTrue(result.hasPRs)
        let weightPR = result.newPRs.first { $0.type == .heaviestWeight }
        XCTAssertNotNil(weightPR)
        XCTAssertEqual(weightPR?.newValue, 90.0)
        XCTAssertNil(weightPR?.oldValue) // First time, no old value
    }

    // MARK: - Most Reps

    func testDetectsMostRepsPR() {
        let sets = [
            ExerciseSetData(exerciseName: "Squat", setNumber: 1, repsCompleted: 8, weightKg: 100.0),
            ExerciseSetData(exerciseName: "Squat", setNumber: 2, repsCompleted: 10, weightKg: 100.0),
            ExerciseSetData(exerciseName: "Squat", setNumber: 3, repsCompleted: 6, weightKg: 100.0)
        ]

        let result = service.detectPRs(from: sets, workoutName: "Leg Day")

        let repsPR = result.newPRs.first { $0.type == .mostReps }
        XCTAssertNotNil(repsPR)
        XCTAssertEqual(repsPR?.newValue, 10.0)
        XCTAssertEqual(repsPR?.weight, 100.0)
    }

    // MARK: - Most Volume

    func testDetectsMostVolumePR() {
        let sets = [
            ExerciseSetData(exerciseName: "Deadlift", setNumber: 1, repsCompleted: 5, weightKg: 120.0),
            ExerciseSetData(exerciseName: "Deadlift", setNumber: 2, repsCompleted: 5, weightKg: 120.0),
            ExerciseSetData(exerciseName: "Deadlift", setNumber: 3, repsCompleted: 3, weightKg: 130.0)
        ]

        let result = service.detectPRs(from: sets, workoutName: "Pull Day")

        let volumePR = result.newPRs.first { $0.type == .mostVolume }
        XCTAssertNotNil(volumePR)
        // 5*120 + 5*120 + 3*130 = 600 + 600 + 390 = 1590
        XCTAssertEqual(volumePR?.newValue, 1590.0)
    }

    // MARK: - Multiple Exercises

    func testHandlesMultipleExercises() {
        let sets = [
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 1, repsCompleted: 5, weightKg: 80.0),
            ExerciseSetData(exerciseName: "Squat", setNumber: 1, repsCompleted: 5, weightKg: 100.0),
            ExerciseSetData(exerciseName: "Deadlift", setNumber: 1, repsCompleted: 3, weightKg: 140.0)
        ]

        let result = service.detectPRs(from: sets, workoutName: "Full Body")

        let exercises = Set(result.newPRs.map { $0.exerciseName })
        XCTAssertTrue(exercises.contains("Bench Press"))
        XCTAssertTrue(exercises.contains("Squat"))
        XCTAssertTrue(exercises.contains("Deadlift"))
    }

    // MARK: - Zero Weight

    func testIgnoresZeroWeightSets() {
        let sets = [
            ExerciseSetData(exerciseName: "Push-ups", setNumber: 1, repsCompleted: 20, weightKg: 0.0),
            ExerciseSetData(exerciseName: "Push-ups", setNumber: 2, repsCompleted: 15, weightKg: 0.0)
        ]

        let result = service.detectPRs(from: sets, workoutName: "Bodyweight")
        XCTAssertFalse(result.hasPRs)
    }

    // MARK: - Beats Existing PR

    func testBeatsExistingPR() {
        // First workout sets a PR
        let firstSets = [
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 1, repsCompleted: 5, weightKg: 80.0)
        ]
        _ = service.detectPRs(from: firstSets, workoutName: "First")

        // Second workout beats it
        let secondSets = [
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 1, repsCompleted: 3, weightKg: 85.0)
        ]
        let result = service.detectPRs(from: secondSets, workoutName: "Second")

        let weightPR = result.newPRs.first { $0.type == .heaviestWeight }
        XCTAssertNotNil(weightPR)
        XCTAssertEqual(weightPR?.newValue, 85.0)
        XCTAssertEqual(weightPR?.oldValue, 80.0)
    }

    // MARK: - Does Not Beat Existing

    func testDoesNotTriggerWhenBelowExistingPR() {
        // First workout
        let firstSets = [
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 1, repsCompleted: 5, weightKg: 100.0)
        ]
        _ = service.detectPRs(from: firstSets, workoutName: "Heavy Day")

        // Lighter workout
        let secondSets = [
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 1, repsCompleted: 5, weightKg: 80.0)
        ]
        let result = service.detectPRs(from: secondSets, workoutName: "Light Day")

        let weightPR = result.newPRs.first { $0.type == .heaviestWeight }
        XCTAssertNil(weightPR)
    }

    // MARK: - Persistence

    func testPRsArePersisted() {
        let sets = [
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 1, repsCompleted: 5, weightKg: 80.0)
        ]
        _ = service.detectPRs(from: sets, workoutName: "Test")

        let storedPRs = service.loadPRs()
        XCTAssertFalse(storedPRs.isEmpty)
        XCTAssertEqual(storedPRs.first?.exerciseName, "Bench Press")
    }

    // MARK: - Grouping

    func testPRsByExerciseGroupsCorrectly() {
        // Create PRs for multiple exercises
        let sets = [
            ExerciseSetData(exerciseName: "Bench Press", setNumber: 1, repsCompleted: 5, weightKg: 80.0),
            ExerciseSetData(exerciseName: "Squat", setNumber: 1, repsCompleted: 5, weightKg: 100.0)
        ]
        _ = service.detectPRs(from: sets, workoutName: "Full Body")

        let grouped = service.prsByExercise()
        XCTAssertEqual(grouped.count, 2)
        // Sorted alphabetically
        XCTAssertEqual(grouped[0].exerciseName, "Bench Press")
        XCTAssertEqual(grouped[1].exerciseName, "Squat")
    }
}
