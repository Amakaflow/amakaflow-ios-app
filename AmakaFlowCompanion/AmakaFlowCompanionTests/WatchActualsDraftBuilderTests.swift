//
//  WatchActualsDraftBuilderTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2420 Phase 2 — Watch set logs → Today Actuals draft + load hint parse.
//

import XCTest
@testable import AmakaFlowCompanion

final class WatchActualsDraftBuilderTests: XCTestCase {

    // MARK: - StandaloneLoadHint

    func testMakeFillInSessionMarksAsPlannedWhenAutoConfirmed() throws {
        let summary = makeSummary(setLogs: [
            StandaloneSetLog(
                exerciseName: "Press",
                exerciseIndex: 0,
                sets: [
                    StandaloneSetEntry(
                        setNumber: 1,
                        weight: 40,
                        unit: "kg",
                        completed: true,
                        detectionMethod: "autoConfirmed"
                    )
                ]
            )
        ])

        let session = try XCTUnwrap(
            WatchActualsDraftBuilder.makeFillInSession(summary: summary, libraryWorkout: nil)
        )
        XCTAssertEqual(session.exercises[0].confirmation, .asPlanned)
    }

    func testMakeFillInSessionDoesNotMarkAsPlannedWithEmptyCompletedSets() throws {
        let summary = makeSummary(setLogs: [
            StandaloneSetLog(
                exerciseName: "Press",
                exerciseIndex: 0,
                sets: [
                    StandaloneSetEntry(
                        setNumber: 1,
                        weight: 40,
                        unit: "kg",
                        completed: false,
                        detectionMethod: "autoConfirmed"
                    )
                ]
            )
        ])

        let session = try XCTUnwrap(
            WatchActualsDraftBuilder.makeFillInSession(summary: summary, libraryWorkout: nil)
        )
        // No completed sets → still builds a row, but must not vacuous-.asPlanned
        XCTAssertNil(session.exercises[0].confirmation)
    }

    func testLoadHintParsesKg() {
        let parsed = StandaloneLoadHint.parse("100 kg")
        XCTAssertEqual(parsed?.weight, 100)
        XCTAssertEqual(parsed?.unit, "kg")
    }

    func testLoadHintParsesLbsCompact() {
        let parsed = StandaloneLoadHint.parse("225lbs")
        XCTAssertEqual(parsed?.weight, 225)
        XCTAssertEqual(parsed?.unit, "lbs")
    }

    func testLoadHintIgnoresEmpty() {
        XCTAssertNil(StandaloneLoadHint.parse(nil))
        XCTAssertNil(StandaloneLoadHint.parse("  "))
        XCTAssertNil(StandaloneLoadHint.parse("bodyweight"))
    }

    // MARK: - Draft builder

    func testMakeFillInSessionOverlaysConfirmedReps() throws {
        let summary = makeSummary(setLogs: [
            StandaloneSetLog(
                exerciseName: "Curl",
                exerciseIndex: 0,
                sets: [
                    StandaloneSetEntry(
                        setNumber: 1,
                        weight: 20,
                        unit: "kg",
                        completed: true,
                        detectionMethod: "inferred",
                        reps: 9
                    )
                ]
            )
        ])
        let library = Workout(
            id: "lib-curl",
            name: "Arms",
            sport: .strength,
            duration: 30 * 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 3,
                    exercises: [
                        Exercise(
                            name: "Curl",
                            canonicalName: nil,
                            sets: 3,
                            reps: "10",
                            durationSeconds: nil,
                            load: ExerciseLoad(value: 20, unit: "kg"),
                            restSeconds: 60,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )

        let session = try XCTUnwrap(
            WatchActualsDraftBuilder.makeFillInSession(summary: summary, libraryWorkout: library)
        )
        XCTAssertEqual(session.exercises[0].name, "Curl")
        XCTAssertEqual(session.exercises[0].actualReps, 9)
        XCTAssertNil(session.exercises[0].confirmation)
    }

    func testMakeFillInSessionFromSetLogsAloneUsesConfirmedReps() throws {
        let summary = makeSummary(setLogs: [
            StandaloneSetLog(
                exerciseName: "Curl",
                exerciseIndex: 0,
                sets: [
                    StandaloneSetEntry(
                        setNumber: 1,
                        weight: 20,
                        unit: "kg",
                        completed: true,
                        detectionMethod: "inferred",
                        reps: 9
                    )
                ]
            )
        ])

        let session = try XCTUnwrap(
            WatchActualsDraftBuilder.makeFillInSession(summary: summary, libraryWorkout: nil)
        )
        XCTAssertEqual(session.exercises[0].actualReps, 9)
        XCTAssertNil(session.exercises[0].confirmation)
    }

    func testMakeFillInSessionFromSetLogsAlone() throws {
        let summary = makeSummary(setLogs: [
            StandaloneSetLog(
                exerciseName: "Back Squat",
                exerciseIndex: 0,
                sets: [
                    StandaloneSetEntry(setNumber: 1, weight: 100, unit: "kg", completed: true),
                    StandaloneSetEntry(setNumber: 2, weight: 105, unit: "kg", completed: true),
                ]
            )
        ])

        let session = WatchActualsDraftBuilder.makeFillInSession(
            summary: summary,
            libraryWorkout: nil
        )

        let unwrapped = try XCTUnwrap(session)
        XCTAssertFalse(unwrapped.verified)
        XCTAssertTrue(unwrapped.id.hasPrefix("watch-"))
        XCTAssertEqual(unwrapped.title, "Watch Strength")
        XCTAssertTrue(unwrapped.subtitle.contains("APPLE WATCH"))
        XCTAssertEqual(unwrapped.exercises.count, 1)
        XCTAssertEqual(unwrapped.exercises[0].name, "Back Squat")
        XCTAssertEqual(unwrapped.exercises[0].actualSets, 2)
        XCTAssertEqual(unwrapped.exercises[0].actualWeightKg, 105)
    }

    func testMakeFillInSessionSeedsBlankExerciseWhenSetLogsEmpty() throws {
        let session = try XCTUnwrap(
            WatchActualsDraftBuilder.makeFillInSession(
                summary: makeSummary(setLogs: nil),
                libraryWorkout: nil
            )
        )
        XCTAssertEqual(session.exercises.count, 1)
        XCTAssertEqual(session.exercises[0].name, "Exercise 1")
        XCTAssertNil(session.exercises[0].confirmation)
        XCTAssertFalse(session.verified)
    }

    func testMakeFillInSessionSeedsBlankExerciseWhenSetLogsEmptyArray() throws {
        let session = try XCTUnwrap(
            WatchActualsDraftBuilder.makeFillInSession(
                summary: makeSummary(setLogs: []),
                libraryWorkout: nil
            )
        )
        XCTAssertEqual(session.exercises.count, 1)
        XCTAssertEqual(session.exercises[0].name, "Exercise 1")
        XCTAssertFalse(session.verified)
    }

    func testMakeFillInSessionConvertsLbsToKg() throws {
        let summary = makeSummary(setLogs: [
            StandaloneSetLog(
                exerciseName: "Bench",
                exerciseIndex: 0,
                sets: [
                    StandaloneSetEntry(setNumber: 1, weight: 135, unit: "lbs", completed: true)
                ]
            )
        ])

        let session = try XCTUnwrap(
            WatchActualsDraftBuilder.makeFillInSession(summary: summary, libraryWorkout: nil)
        )
        let kg = try XCTUnwrap(session.exercises[0].actualWeightKg)
        XCTAssertEqual(kg, 135 * 0.45359237, accuracy: 0.01)
    }

    // MARK: - Completion request mapping

    @MainActor
    func testWatchCompletionIncludesSetLogsWhenPresent() throws {
        let summary = makeSummary(setLogs: [
            StandaloneSetLog(
                exerciseName: "Row",
                exerciseIndex: 0,
                sets: [
                    StandaloneSetEntry(setNumber: 1, weight: 60, unit: "kg", completed: true)
                ]
            )
        ])

        let request = WorkoutCompletionService.makeWatchCompletionRequestForTesting(summary: summary)
        let logs = try XCTUnwrap(request.setLogs)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].exerciseName, "Row")
        XCTAssertEqual(logs[0].sets[0].weight, 60)
        XCTAssertEqual(logs[0].sets[0].unit, "kg")
        XCTAssertTrue(logs[0].sets[0].completed)
    }

    @MainActor
    func testWatchCompletionOmitsSetLogsWhenAbsent() {
        let request = WorkoutCompletionService.makeWatchCompletionRequestForTesting(
            summary: makeSummary(setLogs: nil)
        )
        XCTAssertNil(request.setLogs)
    }

    // MARK: - Helpers

    private func makeSummary(setLogs: [StandaloneSetLog]?) -> StandaloneWorkoutSummary {
        StandaloneWorkoutSummary(
            workoutId: "watch-phase2-1",
            workoutName: "Watch Strength",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            durationSeconds: 3600,
            totalCalories: 200,
            averageHeartRate: 130,
            completedSteps: 8,
            totalSteps: 8,
            setLogs: setLogs
        )
    }
}
