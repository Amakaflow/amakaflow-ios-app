//
//  WorkoutLibraryDetailStoreTests.swift
//  AmakaFlowCompanionTests
//
//  Library detail cache must pick up editor reorders (interval-only GET overlay).
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutLibraryDetailStoreTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "af_library_workout_detail_cache_v1")
        super.tearDown()
    }

    func testSaveAfterEditorReplacesStaleImportBlocks() {
        let workoutID = "wk-detail-\(UUID().uuidString)"
        let stale = Workout(
            id: workoutID,
            name: "Quick Upper",
            sport: .strength,
            duration: 1200,
            blocks: [
                Block(
                    label: "Main",
                    structure: .straight,
                    rounds: 1,
                    exercises: [
                        Exercise(
                            name: "Hammer Curl",
                            canonicalName: nil,
                            sets: 1,
                            reps: "5",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            supersetGroup: nil
                        )
                    ]
                ),
                Block(
                    label: "Block 4",
                    structure: .straight,
                    rounds: 1,
                    exercises: [
                        Exercise(
                            name: "Push Up",
                            canonicalName: nil,
                            sets: 1,
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
        if case .failure(let error) = WorkoutLibraryDetailStore.save(stale) {
            XCTFail("Expected cache save success, got \(error)")
        }

        let saved = Workout(
            id: workoutID,
            name: "Quick Upper",
            sport: .strength,
            duration: 1200,
            intervals: [
                .reps(sets: 1, reps: 10, name: "Push Up", load: nil, restSec: 60, followAlongUrl: nil),
                .reps(sets: 1, reps: 5, name: "Hammer Curl", load: nil, restSec: 60, followAlongUrl: nil)
            ],
            source: .instagram
        )
        let request = WorkoutSaveRequest(
            name: "Quick Upper",
            sport: "strength",
            intervals: [
                WorkoutSaveInterval(type: "reps", name: "Push Up", sets: 1, reps: 10, restSeconds: 60),
                WorkoutSaveInterval(type: "reps", name: "Hammer Curl", sets: 1, reps: 5, restSeconds: 60)
            ],
            source: WorkoutSource.instagram.rawValue,
            blocks: [
                SocialImportBlock(
                    label: nil,
                    rounds: 1,
                    exercises: [
                        SocialImportExercise(name: "Push Up", sets: 1, reps: 10),
                        SocialImportExercise(name: "Hammer Curl", sets: 1, reps: 5)
                    ],
                    type: "sets",
                    structureSource: "user_confirmed"
                )
            ],
            workoutId: workoutID
        )

        if case .failure(let error) = WorkoutLibraryDetailStore.saveAfterEditor(
            saved: saved,
            request: request
        ) {
            XCTFail("Expected editor cache update success, got \(error)")
        }

        let enriched = WorkoutLibraryDetailStore.enrich(saved)
        XCTAssertEqual(
            enriched.blocks.flatMap(\.exercises).map(\.name),
            ["Push Up", "Hammer Curl"]
        )
    }
}
