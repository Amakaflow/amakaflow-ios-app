//
//  WorkoutSportHonestyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2393 — type chip persistence helpers, RECORDS AS labels, disagreement chip.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutSportHonestyTests: XCTestCase {

    func testBikeSkiRowInfersMixedNotStrength() {
        let blocks = [
            Block(
                label: "Main",
                structure: .circuit,
                rounds: 8,
                exercises: [
                    Exercise(
                        name: "Assault Bike", canonicalName: nil, sets: nil, reps: nil,
                        durationSeconds: 180, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    ),
                    Exercise(
                        name: "Ski Erg", canonicalName: nil, sets: nil, reps: nil,
                        durationSeconds: 180, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    ),
                    Exercise(
                        name: "Rowing Machine", canonicalName: nil, sets: nil, reps: nil,
                        durationSeconds: 180, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    ),
                    Exercise(
                        name: "Spin", canonicalName: nil, sets: nil, reps: nil,
                        durationSeconds: 180, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    ),
                ]
            )
        ]
        XCTAssertEqual(WorkoutSportHonesty.inferSport(from: blocks), .mixed)
        XCTAssertTrue(WorkoutSportHonesty.disagrees(stored: .strength, blocks: blocks))
        XCTAssertFalse(WorkoutSportHonesty.disagrees(stored: .mixed, blocks: blocks))
    }

    func testWarmupCardioExcludedFromLiftDay() {
        let blocks = [
            Block(
                label: "Warmup",
                structure: .straight,
                rounds: 1,
                exercises: [
                    Exercise(
                        name: "Assault Bike", canonicalName: nil, sets: nil, reps: nil,
                        durationSeconds: 300, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    )
                ]
            ),
            Block(
                label: "Main",
                structure: .straight,
                rounds: 1,
                exercises: [
                    Exercise(
                        name: "Back Squat", canonicalName: nil, sets: 5, reps: "5",
                        durationSeconds: nil, load: nil, restSeconds: 180, distance: nil,
                        notes: nil, supersetGroup: nil
                    )
                ]
            ),
        ]
        XCTAssertEqual(WorkoutSportHonesty.inferSport(from: blocks), .strength)
        XCTAssertFalse(WorkoutSportHonesty.disagrees(stored: .strength, blocks: blocks))
    }

    func testBuilderCategoryMapsToPersistedSport() {
        XCTAssertEqual(BuilderV3Category.lift.workoutSport, .strength)
        XCTAssertEqual(BuilderV3Category.conditioning.workoutSport, .conditioning)
        XCTAssertEqual(BuilderV3Category.run.workoutSport, .running)
        XCTAssertEqual(BuilderV3Category.recover.workoutSport, .mobility)
        XCTAssertEqual(WorkoutSport.running.rawValue, "run")
        XCTAssertEqual(WorkoutSport.conditioning.rawValue, "conditioning")
    }

    func testRecordsAsLineUsesActivityNotCollapsedSportType() {
        let mixed = Data(#"""
        {"title":"Bike ski row","activity":"mixedCardio","sportType":"strengthTraining","intervals":[]}
        """#.utf8)
        XCTAssertEqual(WorkoutKitSportLabel.recordsAsLabel(from: mixed), "MIXED CARDIO")

        let hiit = Data(#"""
        {"title":"EMOM","activity":"highIntensityIntervalTraining","sportType":"strengthTraining","intervals":[]}
        """#.utf8)
        XCTAssertEqual(WorkoutKitSportLabel.recordsAsLabel(from: hiit), "HIIT")

        let strength = Data(#"""
        {"title":"5x5","activity":"traditionalStrengthTraining","sportType":"strengthTraining","intervals":[]}
        """#.utf8)
        XCTAssertEqual(WorkoutKitSportLabel.recordsAsLabel(from: strength), "STRENGTH")

        let running = Data(#"""
        {"title":"Easy","activity":"running","sportType":"running","intervals":[]}
        """#.utf8)
        XCTAssertEqual(WorkoutKitSportLabel.recordsAsLabel(from: running), "RUN")
    }

    func testDisagreementNeverRewritesSilently() {
        // Selecting the same sport only dismisses the chip — stored value unchanged.
        let blocks = [
            Block(
                label: "Main",
                structure: .circuit,
                rounds: 8,
                exercises: [
                    Exercise(
                        name: "Assault Bike", canonicalName: nil, sets: nil, reps: nil,
                        durationSeconds: 180, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    ),
                    Exercise(
                        name: "Ski Erg", canonicalName: nil, sets: nil, reps: nil,
                        durationSeconds: 180, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    ),
                ]
            )
        ]
        XCTAssertTrue(WorkoutSportHonesty.disagrees(stored: .strength, blocks: blocks))
        // Confirming strength keeps disagreement true until user picks a new type
        // (UI dismisses via local flag — inference itself never mutates sport).
        XCTAssertEqual(WorkoutSportHonesty.inferSport(from: blocks), .mixed)
    }

    func testEmomWithLiftsInfersConditioning() {
        let blocks = [
            Block(
                label: "Main",
                structure: .emom,
                rounds: 10,
                exercises: [
                    Exercise(
                        name: "KB Swing", canonicalName: nil, sets: 1, reps: "15",
                        durationSeconds: nil, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    ),
                    Exercise(
                        name: "Rowing Machine", canonicalName: nil, sets: nil, reps: nil,
                        durationSeconds: 60, load: nil, restSeconds: nil, distance: nil,
                        notes: nil, supersetGroup: nil
                    ),
                ]
            )
        ]
        XCTAssertEqual(WorkoutSportHonesty.inferSport(from: blocks), .conditioning)
    }

    func testAliasSportCanonicalizedOnSave() throws {
        var request = WorkoutSaveRequest.from(
            workout: Workout(
                name: "Tempo",
                sport: .running,
                duration: 1200,
                blocks: [
                    Block(
                        label: "Main",
                        structure: .straight,
                        rounds: 1,
                        exercises: [
                            Exercise(
                                name: "Easy Run", canonicalName: nil, sets: nil, reps: nil,
                                durationSeconds: 1200, load: nil, restSeconds: nil, distance: nil,
                                notes: nil, supersetGroup: nil
                            )
                        ]
                    )
                ],
                source: .manual
            )
        )
        // Legacy alias must canonicalize to wire value "run" on the mapper body.
        request.sport = "running"
        let body = try APIService.mapperSaveBody(from: request, source: "manual")
        let data = try XCTUnwrap(body["workout_data"] as? [String: Any])
        XCTAssertEqual(data["sport"] as? String, "run")
        XCTAssertEqual(data["workout_type"] as? String, "run")
    }

    func testSaveRequestEncodesCanonicalSport() throws {
        let workout = Workout(
            name: "Bike ski row",
            sport: .conditioning,
            duration: 3600,
            blocks: [
                Block(
                    label: "Main",
                    structure: .circuit,
                    rounds: 8,
                    exercises: [
                        Exercise(
                            name: "Assault Bike", canonicalName: nil, sets: nil, reps: nil,
                            durationSeconds: 180, load: nil, restSeconds: nil, distance: nil,
                            notes: nil, supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        let request = WorkoutSaveRequest.from(workout: workout)
        XCTAssertEqual(request.sport, "conditioning")
        let body = try APIService.mapperSaveBody(from: request, source: "manual")
        let data = try XCTUnwrap(body["workout_data"] as? [String: Any])
        XCTAssertEqual(data["sport"] as? String, "conditioning")
        XCTAssertEqual(data["workout_type"] as? String, "conditioning")
    }
}
