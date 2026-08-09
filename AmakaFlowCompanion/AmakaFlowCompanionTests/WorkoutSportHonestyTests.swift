//
//  WorkoutSportHonestyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2393 — type chip persistence helpers, RECORDS AS labels, disagreement chip.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutSportHonestyTests: XCTestCase {

    // MARK: - AMA-2395 modality chips (same classifier list as the sport inference)

    private func named(_ name: String, sets: Int? = nil, reps: String? = nil) -> Exercise {
        Exercise(
            name: name, canonicalName: nil, sets: sets, reps: reps,
            durationSeconds: nil, load: nil, restSeconds: nil, distance: nil,
            notes: nil, supersetGroup: nil
        )
    }

    /// The dumbbell-on-Ski-Erg bug: cardio machines get the cardio chip.
    func testCardioMachinesAreNeverLifts() {
        for name in ["Ski Erg", "SkiErg", "Rowing Machine", "Assault Bike", "Spin / Indoor Bike",
                     "Treadmill", "Elliptical", "Stair Climber"] {
            XCTAssertEqual(
                WorkoutSportHonesty.modality(for: named(name)), .cardioMachine,
                "\(name) must wear the cardio chip, not a dumbbell"
            )
        }
    }

    func testLiftsRunsAndBodyweightSplitCorrectly() {
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Back Squat")), .lift)
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Dumbbell Row")), .lift)
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Ring Row")), .lift)
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Tempo Run")), .run)
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Plank")), .bodyweight)
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Jump Rope")), .bodyweight)
    }

    /// Unknown names fall back to the neutral chip, not a wrong guess — unless
    /// sets/reps prove it is countable work.
    func testUnknownNamesFallBackToNeutral() {
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Farmer Carry")), .unknown)
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Sled Drag", sets: 3, reps: "10")), .lift)
    }

    /// The load tag only wins when the NAME isn't a machine — a bodyweight-
    /// tagged Assault Bike is still a bike.
    func testBodyweightLoadDoesNotOverrideAMachineName() {
        func loaded(_ name: String) -> Exercise {
            Exercise(
                name: name, canonicalName: nil, sets: nil, reps: nil,
                durationSeconds: 180, load: ExerciseLoad(value: 0, unit: "bodyweight"),
                restSeconds: nil, distance: nil, notes: nil, supersetGroup: nil
            )
        }
        XCTAssertEqual(WorkoutSportHonesty.modality(for: loaded("Assault Bike")), .cardioMachine)
        XCTAssertEqual(WorkoutSportHonesty.modality(for: loaded("Farmer Carry")), .bodyweight)
    }

    func testBurpeesAreBodyweightNotLifts() {
        XCTAssertEqual(WorkoutSportHonesty.modality(for: named("Burpee")), .bodyweight)
    }

    func testDominantModalityDrivesDerivedSectionNames() {
        XCTAssertEqual(
            WorkoutSportHonesty.dominantModality(of: [named("Rowing Machine"), named("Assault Bike")]),
            .cardioMachine
        )
        XCTAssertEqual(
            WorkoutSportHonesty.dominantModality(of: [named("Plank"), named("Hollow Hold")]),
            .bodyweight
        )
        XCTAssertEqual(WorkoutSportHonesty.dominantModality(of: []), .unknown)
    }

    /// The estimator's pace table keys off the SAME machine table.
    func testMachineKindKeyIsSharedWithThePaceTable() {
        XCTAssertEqual(WorkoutSportHonesty.machineKindKey(forName: "Ski Erg"), "ski")
        XCTAssertEqual(WorkoutSportHonesty.machineKindKey(forName: "Rowing"), "row")
        XCTAssertEqual(WorkoutSportHonesty.machineKindKey(forName: "Assault Bike"), "bike")
        XCTAssertNil(WorkoutSportHonesty.machineKindKey(forName: "Back Squat"))
    }

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

    func testLegacyWorkoutTypeDecodesWhenSportAbsent() throws {
        let decoder = JSONDecoder()
        let runningJSON = """
        {"id":"w1","name":"Tempo","workout_type":"running","duration":1200,"blocks":[]}
        """.data(using: .utf8)!
        let hiitJSON = """
        {"id":"w2","name":"EMOM","workout_type":"hiit","duration":600,"blocks":[]}
        """.data(using: .utf8)!
        XCTAssertEqual(try decoder.decode(Workout.self, from: runningJSON).sport, .running)
        XCTAssertEqual(try decoder.decode(Workout.self, from: hiitJSON).sport, .conditioning)
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
        XCTAssertNil(data["workout_type"])
    }

    func testWorkoutKitActivityAliasesParse() {
        XCTAssertEqual(WorkoutSport.parse("traditionalStrengthTraining"), .strength)
        XCTAssertEqual(WorkoutSport.parse("strengthTraining"), .strength)
        XCTAssertEqual(WorkoutSport.parse("mixedCardio"), .mixed)
        XCTAssertEqual(WorkoutSport.parse("highIntensityIntervalTraining"), .conditioning)
        XCTAssertEqual(WorkoutSport.parse("hyrox"), .other)
        XCTAssertEqual(WorkoutSport.parse("HYROX"), .other)
    }

    func testExerciseRowIconsDifferentiateCardioMachines() {
        XCTAssertEqual(WorkoutSportHonesty.systemImage(forExerciseName: "Assault Bike"), "bicycle")
        XCTAssertEqual(WorkoutSportHonesty.systemImage(forExerciseName: "Ski Erg"), "figure.skiing.crosscountry")
        XCTAssertEqual(WorkoutSportHonesty.systemImage(forExerciseName: "Rowing Machine"), "figure.rower")
        XCTAssertEqual(WorkoutSportHonesty.systemImage(forExerciseName: "Back Squat"), "dumbbell.fill")
    }

    func testHeroPillNeverUsesHyroxTitleHeuristic() {
        let pill = WorkoutSportHonesty.heroPill(
            sport: .strength,
            workoutName: "HYROX — Lower body work"
        )
        XCTAssertEqual(pill, "STRENGTH")
        XCTAssertNotEqual(pill, "HYROX")
        XCTAssertEqual(
            WorkoutSportHonesty.heroPill(sport: .conditioning, workoutName: "Hyrox workout"),
            "CONDITIONING"
        )
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
        XCTAssertNil(data["workout_type"])
    }
}
