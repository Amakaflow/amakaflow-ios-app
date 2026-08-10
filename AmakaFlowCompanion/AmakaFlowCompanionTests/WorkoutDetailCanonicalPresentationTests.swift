//
//  WorkoutDetailCanonicalPresentationTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2395 — detail presentation invariants: structure fidelity, no ~1 MIN,
//  library meta, section titles from stored fields only.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutDetailCanonicalPresentationTests: XCTestCase {

    private func setsOnly(_ name: String, sets: Int) -> Exercise {
        Exercise(
            name: name,
            canonicalName: nil,
            sets: sets,
            reps: nil,
            durationSeconds: nil,
            load: nil,
            restSeconds: nil,
            distance: nil,
            notes: nil,
            focus: nil,
            supersetGroup: nil
        )
    }

    private func timed(_ name: String, seconds: Int) -> Exercise {
        Exercise(
            name: name,
            canonicalName: nil,
            sets: nil,
            reps: nil,
            durationSeconds: seconds,
            load: nil,
            restSeconds: nil,
            distance: nil,
            notes: nil,
            focus: nil,
            supersetGroup: nil
        )
    }

    // MARK: - Structure fidelity

    func testOneBlockOneSectionSameMembersAndOrder() {
        let exercises = [
            setsOnly("Incline Smith Machine Press", sets: 5),
            setsOnly("Machine Pec Deck", sets: 3),
            setsOnly("Machine Lateral Raises", sets: 3),
            Exercise(
                name: "Weighted Pull-Ups",
                canonicalName: nil,
                sets: 3,
                reps: "6",
                durationSeconds: nil,
                load: nil,
                restSeconds: nil,
                distance: nil,
                notes: nil,
                focus: nil,
                supersetGroup: nil
            ),
            setsOnly("Machine Rows", sets: 3),
            setsOnly("Easy Bar Preacher Curls", sets: 3),
            setsOnly("Triceps Press Downs", sets: 3),
        ]
        let workout = Workout(
            id: "jeff",
            name: "High Intensity Upper Body",
            sport: .strength,
            duration: 60,
            blocks: [Block(label: nil, structure: .straight, rounds: 1, exercises: exercises)],
            description: "Here's the 45-minute workout. #upperbody",
            source: .instagram,
            sourceUrl: "https://www.instagram.com/jeffnippard",
            creatorName: "jeffnippard"
        )

        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].exercises.map(\.name), exercises.map(\.name))
        XCTAssertTrue(sections[0].title.isEmpty, "Unlabeled straight block must not invent a heading")
        XCTAssertFalse(sections[0].note.contains("~"))
        XCTAssertEqual(sections[0].note, "≈ 46 MIN")
    }

    func testPlaceholderBlockLabelNeverRenders() {
        let workout = Workout(
            id: "blocks",
            name: "Legacy",
            sport: .strength,
            duration: 60,
            blocks: [
                Block(label: "Block 7", structure: .straight, rounds: 1, exercises: [setsOnly("Squat", sets: 3)]),
                Block(label: "Main", structure: .straight, rounds: 1, exercises: [setsOnly("Bench", sets: 3)]),
                Block(label: "Finisher", structure: .circuit, rounds: 5, exercises: [timed("Ski Erg", seconds: 60)]),
            ],
            source: .ai
        )
        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 3)
        XCTAssertTrue(sections[0].title.isEmpty)
        XCTAssertTrue(sections[1].title.isEmpty)
        XCTAssertTrue(sections[2].title.contains("FINISHER"))
        XCTAssertFalse(sections.contains { $0.title.localizedCaseInsensitiveContains("Block") })
        XCTAssertFalse(sections.contains { $0.title.contains("ROTATE") })
    }

    func testCircuitTitleFromStoredStructureOnly() {
        let workout = Workout(
            id: "circuit",
            name: "Bike ski row repeats",
            sport: .cardio,
            duration: 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .circuit,
                    rounds: 8,
                    exercises: [
                        timed("Assault Bike", seconds: 180),
                        timed("Ski Erg", seconds: 180),
                        timed("Rowing Machine", seconds: 180),
                        timed("Spin / Indoor Bike", seconds: 180),
                    ]
                )
            ],
            source: .manual
        )
        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "CIRCUIT · 8 ROUNDS")
        XCTAssertEqual(sections[0].note, "96 MIN")
        XCTAssertFalse(sections[0].note.contains("≈"))
    }

    // MARK: - Duration display

    func testMinuteLabelNeverProducesTildeOneMin() {
        let cases: [(Int, Bool)] = [
            (0, true), (45, true), (60, false), (3728, true), (5760, false)
        ]
        for (seconds, isEstimate) in cases {
            let label = WorkoutDurationEstimate.minuteLabel(seconds: seconds, isEstimate: isEstimate)
            XCTAssertFalse(label.contains("~"), label)
            XCTAssertFalse(label == "~1 MIN", label)
        }
    }

    func testBogusStoredDurationOverriddenByStructure() {
        let workout = Workout(
            id: "bogus",
            name: "Circuit",
            sport: .cardio,
            duration: 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .circuit,
                    rounds: 8,
                    exercises: [
                        timed("Assault Bike", seconds: 180),
                        timed("Ski Erg", seconds: 180),
                        timed("Rowing Machine", seconds: 180),
                        timed("Spin", seconds: 180),
                    ]
                )
            ],
            source: .manual
        )
        let estimate = WorkoutDurationEstimator.estimate(for: workout)
        XCTAssertEqual(estimate.minuteLabel, "96 MIN")

        let meta = DDLibraryPresentation.row(for: workout).meta
        XCTAssertTrue(meta.contains("96 min"), meta)
        XCTAssertFalse(meta.contains("~1"), meta)
        XCTAssertFalse(meta.contains("· 1 min"), "Got: \(meta)")
        XCTAssertFalse(meta.hasPrefix("1 min"), "Got: \(meta)")
    }

    func testJeffSetsOnlyEstimateNearCreator45() {
        let workout = Workout(
            id: "jeff",
            name: "High Intensity Upper Body",
            sport: .strength,
            duration: 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .straight,
                    rounds: 1,
                    exercises: [
                        setsOnly("Incline Smith Machine Press", sets: 5),
                        setsOnly("Machine Pec Deck", sets: 3),
                        setsOnly("Machine Lateral Raises", sets: 3),
                        Exercise(
                            name: "Weighted Pull-Ups",
                            canonicalName: nil,
                            sets: 3,
                            reps: "6",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        ),
                        setsOnly("Machine Rows", sets: 3),
                        setsOnly("Easy Bar Preacher Curls", sets: 3),
                        setsOnly("Triceps Press Downs", sets: 3),
                    ]
                )
            ],
            source: .instagram
        )
        let estimate = WorkoutDurationEstimator.estimate(for: workout)
        XCTAssertEqual(estimate.minuteLabel, "≈ 46 MIN")
        XCTAssertTrue(estimate.basisNote.contains("1 MIN WORK"))
        XCTAssertEqual(estimate.activeSublabel, "SETS · 1 MIN WORK + 1 MIN REST")
    }

    // MARK: - Bundled fixture validation (AMA-2395 dogfood anchors)

    func testJeffFixtureJSONSetsOnlyNearCreator45() throws {
        #if DEBUG
        let workout = try FixtureLoader.loadFixture(named: "jeff_nippard_upper_body")
        XCTAssertEqual(workout.name, "High Intensity Upper Body")
        XCTAssertEqual(workout.creatorName, "jeffnippard")
        XCTAssertEqual(workout.duration, 60, "stored duration is the old ~1 MIN trap")

        let estimate = WorkoutDurationEstimator.estimate(for: workout)
        XCTAssertEqual(estimate.totalSec, 2769)
        XCTAssertEqual(estimate.minuteLabel, "≈ 46 MIN")
        XCTAssertTrue(estimate.isEstimate)
        XCTAssertTrue(estimate.basisNote.contains("1 MIN WORK"))
        XCTAssertEqual(estimate.activeSublabel, "SETS · 1 MIN WORK + 1 MIN REST")
        XCTAssertFalse(estimate.minuteLabel.contains("~"))

        let creatorSec = 45 * 60
        let delta = abs(Double(estimate.totalSec - creatorSec) / Double(creatorSec))
        XCTAssertLessThanOrEqual(delta, 0.15)

        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].note, "≈ 46 MIN")
        XCTAssertTrue(sections[0].title.isEmpty)
        XCTAssertEqual(sections[0].exercises.count, 7)
        XCTAssertEqual(sections[0].exercises.first?.name, "Incline Smith Machine Press")

        let meta = DDLibraryPresentation.row(for: workout).meta
        XCTAssertTrue(meta.contains("46 min"), "Library row must not show 1 min. Got: \(meta)")
        XCTAssertFalse(meta.contains("~1"), meta)

        let caption = WorkoutCaptionPresentation.present(workout.description)
        XCTAssertNotNil(caption)
        XCTAssertTrue(caption?.collapsed.contains("45-minute") ?? false)
        XCTAssertFalse(caption?.collapsed.contains("#jeffnippard") ?? true)
        #else
        throw XCTSkip("FixtureLoader is DEBUG-only")
        #endif
    }

    func testBikeSkiRowFixtureJSONExact96() throws {
        #if DEBUG
        let workout = try FixtureLoader.loadFixture(named: "bike_ski_row_circuit")
        XCTAssertEqual(workout.name, "Bike ski row repeats")
        XCTAssertEqual(workout.duration, 60)

        let estimate = WorkoutDurationEstimator.estimate(for: workout)
        XCTAssertEqual(estimate.totalSec, 5760)
        XCTAssertEqual(estimate.minuteLabel, "96 MIN")
        XCTAssertFalse(estimate.isEstimate)
        XCTAssertFalse(estimate.minuteLabel.contains("≈"))
        XCTAssertFalse(estimate.minuteLabel.contains("~"))

        let sections = DDWorkoutDisplayGrouping.sections(for: workout)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "CIRCUIT · 8 ROUNDS")
        XCTAssertEqual(sections[0].note, "96 MIN")
        XCTAssertEqual(sections[0].exercises.map(\.name), [
            "Assault Bike", "Ski Erg", "Rowing Machine", "Spin / Indoor Bike",
        ])

        let meta = DDLibraryPresentation.row(for: workout).meta
        XCTAssertTrue(meta.contains("96 min"), meta)
        XCTAssertFalse(meta.contains("~1"), meta)
        #else
        throw XCTSkip("FixtureLoader is DEBUG-only")
        #endif
    }

    // MARK: - Modality chips share AMA-2393 classifier

    func testModalityClassifierSkiRowBikeAreCardio() {
        XCTAssertEqual(WorkoutSportHonesty.modalityChipKind(forExerciseName: "Ski Erg"), .cardio)
        XCTAssertEqual(WorkoutSportHonesty.modalityChipKind(forExerciseName: "Rowing Machine"), .cardio)
        XCTAssertEqual(WorkoutSportHonesty.modalityChipKind(forExerciseName: "Assault Bike"), .cardio)
        XCTAssertEqual(WorkoutSportHonesty.machineKindKey(forExerciseName: "Ski Erg"), "ski")
        XCTAssertEqual(WorkoutSportHonesty.systemImage(forExerciseName: "Ski Erg"), "figure.skiing.crosscountry")
        XCTAssertNotEqual(WorkoutSportHonesty.systemImage(forExerciseName: "Ski Erg"), "dumbbell.fill")
    }
}
