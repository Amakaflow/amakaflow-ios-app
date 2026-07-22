//
//  WorkoutEditorSaveTests.swift
//  AmakaFlowCompanionTests
//
//  Editor save must hit mapper body + workout_id so edits/reorders persist.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutEditorSaveTests: XCTestCase {

    private var mockAPI: MockAPIService!
    private var deps: AppDependencies!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI = await MockAPIService()
        let pairing = await MockPairingService()
        deps = AppDependencies(
            apiService: mockAPI,
            pairingService: pairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
    }

    override func tearDown() async throws {
        mockAPI = nil
        deps = nil
        try await super.tearDown()
    }

    func testEditSaveSendsWorkoutIdAndSource() async {
        let workout = Workout(
            id: "wk-edit-1",
            name: "Upper",
            sport: .strength,
            duration: 1800,
            intervals: [
                .reps(sets: 3, reps: 10, name: "Bench", load: nil, restSec: 60, followAlongUrl: nil),
                .reps(sets: 3, reps: 10, name: "Row", load: nil, restSec: 60, followAlongUrl: nil)
            ],
            source: .instagram,
            sourceUrl: "https://www.instagram.com/reel/ABC/"
        )
        mockAPI.saveWorkoutResult = .success(workout)

        let sut = WorkoutEditorViewModel(workout: workout, dependencies: deps)
        sut.intervals = [
            WorkoutSaveInterval(type: "reps", name: "Row", sets: 3, reps: 10, restSeconds: 60),
            WorkoutSaveInterval(type: "reps", name: "Bench", sets: 3, reps: 10, restSeconds: 60)
        ]
        sut.saveBlocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Row", sets: 3, reps: 10),
                    SocialImportExercise(name: "Bench", sets: 3, reps: 10)
                ]
            )
        ]

        await sut.save()

        XCTAssertTrue(sut.didSave)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(mockAPI.saveWorkoutCalled)
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.workoutId, "wk-edit-1")
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.source, WorkoutSource.instagram.rawValue)
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.name, "Upper")
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.blocks?.first?.exercises.first?.name, "Row")
    }

    func testNewSaveDefaultsToManualSourceWithoutWorkoutId() async {
        mockAPI.saveWorkoutResult = .success(
            Workout(
                id: "wk-new",
                name: "Scratch",
                sport: .strength,
                duration: 600,
                intervals: [],
                source: .manual
            )
        )
        let sut = WorkoutEditorViewModel(dependencies: deps)
        sut.name = "Scratch"
        sut.intervals = [
            WorkoutSaveInterval(type: "reps", name: "Squat", sets: 3, reps: 10, restSeconds: 60)
        ]

        await sut.save()

        XCTAssertTrue(sut.didSave)
        XCTAssertNil(mockAPI.lastSaveWorkoutRequest?.workoutId)
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.source, WorkoutSource.manual.rawValue)
    }

    func testMapperSaveBodyIncludesWorkoutIdForUpdates() throws {
        let request = WorkoutSaveRequest(
            name: "Upper",
            sport: "strength",
            intervals: [WorkoutSaveInterval(type: "reps", name: "Bench", sets: 3, reps: 8)],
            source: WorkoutSource.instagram.rawValue,
            workoutId: "wk-edit-1"
        )
        let body = try APIService.mapperSaveBody(from: request, source: WorkoutSource.instagram.rawValue)
        XCTAssertEqual(body["workout_id"] as? String, "wk-edit-1")
        XCTAssertEqual(body["device"] as? String, "ios")
        XCTAssertNotNil(body["workout_data"])
    }

    func testMapperSaveBodyDefaultsWithoutWorkoutIdForCreates() throws {
        let request = WorkoutSaveRequest(
            name: "Scratch",
            sport: "strength",
            intervals: [WorkoutSaveInterval(type: "reps", name: "Squat", sets: 3, reps: 10)],
            source: WorkoutSource.manual.rawValue
        )
        let body = try APIService.mapperSaveBody(from: request, source: WorkoutSource.manual.rawValue)
        XCTAssertNil(body["workout_id"])
        XCTAssertEqual(body["sources"] as? [String], ["manual"])
    }
}
