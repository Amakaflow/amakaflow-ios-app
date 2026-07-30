//
//  MapperBlockCircuitTypeTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2343 A+D: persist type=circuit when Companion shows a circuit;
//  never stamp type=warmup on author multi-round sections.
//

import XCTest
@testable import AmakaFlowCompanion

final class MapperBlockCircuitTypeTests: XCTestCase {

    func testTypelessWarmUpRoundsPersistsCircuit() {
        let block = SocialImportBlock(
            label: "Warm-Up",
            rounds: 3,
            exercises: [
                SocialImportExercise(name: "Ski Erg"),
                SocialImportExercise(name: "Push Up", reps: 10),
                SocialImportExercise(name: "Ring Row", reps: 10),
                SocialImportExercise(name: "Inchworm", reps: 5),
                SocialImportExercise(name: "Band Pull Apart", reps: 20)
            ]
        )
        let object = APIService.mapperBlockObject(from: block)
        XCTAssertEqual(object["type"] as? String, StructureBlockType.circuit.rawValue)
        XCTAssertEqual(object["rounds"] as? Int, 3)
        XCTAssertEqual(object["label"] as? String, "Warm-Up")
        XCTAssertNotEqual(object["type"] as? String, StructureBlockType.warmup.rawValue)
    }

    func testExplicitSoftWarmupKeepsWarmupType() {
        let block = SocialImportBlock(
            label: "Mobility prep",
            rounds: 1,
            exercises: [SocialImportExercise(name: "Jump Rope", seconds: 120)],
            type: StructureBlockType.warmup.rawValue,
            structureSource: StructureSource.enrichmentDefault.rawValue,
            enrichmentKind: EnrichmentKind.sessionWarmup.rawValue
        )
        let object = APIService.mapperBlockObject(from: block)
        XCTAssertEqual(object["type"] as? String, StructureBlockType.warmup.rawValue)
        XCTAssertNil(object["rounds"])
    }

    func testStrengthWithPerExerciseSetsDoesNotInferCircuit() {
        let block = SocialImportBlock(
            label: "Main",
            rounds: 3,
            exercises: [
                SocialImportExercise(name: "Bench Press", sets: 3, reps: 10),
                SocialImportExercise(name: "Squat", sets: 3, reps: 8)
            ]
        )
        let object = APIService.mapperBlockObject(from: block)
        XCTAssertNil(object["type"])
        XCTAssertEqual(object["rounds"] as? Int, 3)
    }

    func testExplicitCircuitTypePreserved() {
        let block = SocialImportBlock(
            label: "WARM-UP",
            rounds: 3,
            exercises: [
                SocialImportExercise(name: "Ski Erg"),
                SocialImportExercise(name: "Push Up", reps: 10)
            ],
            type: StructureBlockType.circuit.rawValue
        )
        let object = APIService.mapperBlockObject(from: block)
        XCTAssertEqual(object["type"] as? String, StructureBlockType.circuit.rawValue)
    }

    func testBlocksFromWorkoutInfersCircuitForStraightRounds() throws {
        let workout = Workout(
            id: "wk-1",
            name: "Hyrox",
            sport: .strength,
            duration: 1200,
            blocks: [
                Block(
                    label: "Warm-Up",
                    structure: .straight,
                    rounds: 3,
                    exercises: [
                        Exercise(
                            name: "Ski Erg",
                            canonicalName: nil,
                            sets: nil,
                            reps: nil,
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            supersetGroup: nil
                        ),
                        Exercise(
                            name: "Push Up",
                            canonicalName: nil,
                            sets: nil,
                            reps: "10",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .instagram
        )
        let request = WorkoutSaveRequest.from(workout: workout)
        let blocks = try XCTUnwrap(request.blocks)
        XCTAssertEqual(blocks.first?.type, StructureBlockType.circuit.rawValue)
        XCTAssertEqual(blocks.first?.rounds, 3)

        let body = try APIService.mapperSaveBody(from: request, source: "instagram")
        let workoutData = try XCTUnwrap(body["workout_data"] as? [String: Any])
        let mapped = try XCTUnwrap(workoutData["blocks"] as? [[String: Any]])
        XCTAssertEqual(mapped.first?["type"] as? String, "circuit")
    }

    func testOfferTitleUsesMobilityPrepCopy() {
        let offer = WorkoutEnrichmentPushPlanner.Offer(
            kind: .sessionWarmup,
            isChecked: true,
            wasTombstoned: false,
            detail: "Jump Rope · until Lap",
            tombstonedExerciseIds: []
        )
        XCTAssertEqual(offer.title, "Add mobility prep")
    }
}
