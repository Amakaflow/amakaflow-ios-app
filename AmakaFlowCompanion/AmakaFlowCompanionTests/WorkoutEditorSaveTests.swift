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
        UserDefaults.standard.removeObject(forKey: "af_library_workout_detail_cache_v1")
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
            description: "Push day from reel",
            source: .instagram,
            sourceUrl: "https://www.instagram.com/reel/ABC/",
            creatorName: "coach_dave"
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
                ],
                structureSource: "explicit"
            )
        ]

        await sut.save()

        XCTAssertTrue(sut.didSave)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(mockAPI.saveWorkoutCalled)
        let saved = mockAPI.lastSaveWorkoutRequest
        XCTAssertEqual(saved?.workoutId, "wk-edit-1")
        XCTAssertEqual(saved?.source, WorkoutSource.instagram.rawValue)
        XCTAssertEqual(saved?.sourceUrl, "https://www.instagram.com/reel/ABC/")
        XCTAssertEqual(saved?.description, "Push day from reel")
        XCTAssertEqual(saved?.creatorName, "coach_dave")
        XCTAssertEqual(saved?.name, "Upper")
        XCTAssertEqual(saved?.blocks?.first?.exercises.first?.name, "Row")
        XCTAssertEqual(saved?.blocks?.first?.structureSource, "explicit")
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

    func testMapperSaveBodyIncludesWorkoutIdAndProvenance() throws {
        let request = WorkoutSaveRequest(
            name: "Upper",
            sport: "strength",
            intervals: [],
            source: WorkoutSource.instagram.rawValue,
            sourceUrl: "https://www.instagram.com/reel/ABC/",
            description: "Push day from reel",
            creatorName: "coach_dave",
            blocks: [
                SocialImportBlock(
                    label: "Superset A",
                    rounds: 3,
                    exercises: [
                        SocialImportExercise(name: "Bench", sets: 3, reps: 8)
                    ],
                    type: "superset",
                    structureSource: "explicit"
                )
            ],
            workoutId: "wk-edit-1"
        )
        let body = try APIService.mapperSaveBody(from: request, source: WorkoutSource.instagram.rawValue)
        XCTAssertEqual(body["workout_id"] as? String, "wk-edit-1")
        XCTAssertEqual(body["device"] as? String, "ios")

        let workoutData = try XCTUnwrap(body["workout_data"] as? [String: Any])
        XCTAssertEqual(workoutData["description"] as? String, "Push day from reel")
        let metadata = try XCTUnwrap(workoutData["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["source_url"] as? String, "https://www.instagram.com/reel/ABC/")
        XCTAssertEqual(metadata["creator"] as? String, "coach_dave")

        let blocks = try XCTUnwrap(workoutData["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.first?["structure_source"] as? String, "explicit")
        XCTAssertEqual(blocks.first?["type"] as? String, "superset")
        XCTAssertEqual(blocks.first?["rounds"] as? Int, 3)
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

    func testEditSaveUpdatesLibraryDetailCacheOrder() async {
        let workoutID = "wk-reorder-cache-\(UUID().uuidString)"
        let stale = Workout(
            id: workoutID,
            name: "Upper",
            sport: .strength,
            duration: 1800,
            blocks: [
                Block(label: "Main", structure: .straight, rounds: 1, exercises: [
                    Exercise(
                        name: "Hammer Curl",
                        canonicalName: nil,
                        sets: 1,
                        reps: "5",
                        durationSeconds: nil,
                        load: nil,
                        restSeconds: 60,
                        distance: nil,
                        notes: nil,
                        supersetGroup: nil
                    )
                ]),
                Block(label: "Block 4", structure: .straight, rounds: 1, exercises: [
                    Exercise(
                        name: "Push Up",
                        canonicalName: nil,
                        sets: 1,
                        reps: "10",
                        durationSeconds: nil,
                        load: nil,
                        restSeconds: 60,
                        distance: nil,
                        notes: nil,
                        supersetGroup: nil
                    )
                ])
            ],
            source: .instagram,
            sourceUrl: "https://www.instagram.com/reel/ABC/"
        )
        if case .failure(let error) = WorkoutLibraryDetailStore.save(stale) {
            XCTFail("Expected cache save success, got \(error)")
        }

        // Interval-only reload would otherwise re-surface stale cached blocks.
        let serverReload = Workout(
            id: workoutID,
            name: "Upper",
            sport: .strength,
            duration: 1800,
            intervals: [
                .reps(sets: 1, reps: 10, name: "Push Up", load: nil, restSec: 60, followAlongUrl: nil),
                .reps(sets: 1, reps: 5, name: "Hammer Curl", load: nil, restSec: 60, followAlongUrl: nil)
            ],
            source: .instagram
        )
        mockAPI.saveWorkoutResult = .success(serverReload)

        let sut = WorkoutEditorViewModel(workout: stale, dependencies: deps)
        sut.intervals = [
            WorkoutSaveInterval(type: "reps", name: "Push Up", sets: 1, reps: 10, restSeconds: 60),
            WorkoutSaveInterval(type: "reps", name: "Hammer Curl", sets: 1, reps: 5, restSeconds: 60)
        ]
        sut.saveBlocks = [
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
        ]

        await sut.save()
        XCTAssertTrue(sut.didSave)

        let enriched = WorkoutLibraryDetailStore.enrich(serverReload)
        let names = enriched.blocks.flatMap(\.exercises).map(\.name)
        XCTAssertEqual(names, ["Push Up", "Hammer Curl"])
    }

    /// Create → save → edit sets/reps/order → save again; payload + Library cache must stick.
    func testCreateThenEditSetsAndReorderPersistThroughSaves() async throws {
        // 1) Create new workout
        mockAPI.saveWorkoutResult = .success(
            Workout(
                id: "wk-created-1",
                name: "Garage Upper",
                sport: .strength,
                duration: 900,
                source: .manual
            )
        )

        var session = EditorV2Session(title: "Garage Upper")
        let curl = session.addExercise(named: "Hammer Curl")
        let press = session.addExercise(named: "Curl to Press")
        _ = session.addExercise(named: "Rows")
        _ = session.addExercise(named: "Push Up")

        let createVM = WorkoutEditorViewModel(dependencies: deps)
        createVM.name = session.title
        createVM.intervals = session.toSaveIntervals()
        createVM.saveBlocks = session.toSocialImportBlocks()
        await createVM.save()

        XCTAssertTrue(createVM.didSave)
        XCTAssertNil(mockAPI.lastSaveWorkoutRequest?.workoutId)
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.source, WorkoutSource.manual.rawValue)
        XCTAssertEqual(
            mockAPI.lastSaveWorkoutRequest?.intervals.map(\.name),
            ["Hammer Curl", "Curl to Press", "Rows", "Push Up"]
        )

        // 2) Re-open as edit: bump sets, change reps, reorder Push Up first
        let created = Workout(
            id: "wk-created-1",
            name: "Garage Upper",
            sport: .strength,
            duration: 900,
            blocks: [
                Block(
                    label: "Main",
                    structure: .straight,
                    rounds: 1,
                    exercises: session.toSocialImportBlocks().flatMap(\.exercises).map {
                        Exercise(
                            name: $0.name,
                            canonicalName: nil,
                            sets: $0.sets,
                            reps: $0.reps.map(String.init),
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: 60,
                            distance: nil,
                            notes: nil,
                            supersetGroup: nil
                        )
                    }
                )
            ],
            source: .manual
        )
        if case .failure(let error) = WorkoutLibraryDetailStore.save(created) {
            XCTFail("seed cache failed: \(error)")
        }

        session.addSet(to: curl.id) // 3 → 4
        session.updateExercise(press.id) { $0.reps = 8 }
        session.reorder(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        XCTAssertEqual(session.exercises.map(\.name), [
            "Push Up", "Hammer Curl", "Curl to Press", "Rows"
        ])
        XCTAssertEqual(session.exercises.first(where: { $0.id == curl.id })?.sets, 4)
        XCTAssertEqual(session.exercises.first(where: { $0.id == press.id })?.reps, 8)

        let intervalOnlyReload = Workout(
            id: "wk-created-1",
            name: "Garage Upper",
            sport: .strength,
            duration: 900,
            intervals: session.toSaveIntervals().compactMap { interval in
                guard interval.type == "reps" else { return nil }
                return .reps(
                    sets: interval.sets,
                    reps: interval.reps ?? 10,
                    name: interval.name ?? "",
                    load: interval.load,
                    restSec: interval.restSeconds,
                    followAlongUrl: nil
                )
            },
            source: .manual
        )
        mockAPI.saveWorkoutResult = .success(intervalOnlyReload)

        let editVM = WorkoutEditorViewModel(workout: created, dependencies: deps)
        editVM.name = session.title
        editVM.intervals = session.toSaveIntervals()
        editVM.saveBlocks = session.toSocialImportBlocks()
        await editVM.save()

        XCTAssertTrue(editVM.didSave)
        let editRequest = try XCTUnwrap(mockAPI.lastSaveWorkoutRequest)
        XCTAssertEqual(editRequest.workoutId, "wk-created-1")
        XCTAssertEqual(editRequest.intervals.map(\.name), [
            "Push Up", "Hammer Curl", "Curl to Press", "Rows"
        ])
        XCTAssertEqual(
            editRequest.intervals.first(where: { $0.name == "Hammer Curl" })?.sets,
            4
        )
        XCTAssertEqual(
            editRequest.intervals.first(where: { $0.name == "Curl to Press" })?.reps,
            8
        )
        XCTAssertEqual(
            editRequest.blocks?.flatMap(\.exercises).map(\.name),
            ["Push Up", "Hammer Curl", "Curl to Press", "Rows"]
        )
        XCTAssertEqual(
            editRequest.blocks?.flatMap(\.exercises).first(where: { $0.name == "Hammer Curl" })?.sets,
            4
        )

        // 3) Library enrich after interval-only GET must keep edited sets + order
        let enriched = WorkoutLibraryDetailStore.enrich(intervalOnlyReload)
        let enrichedExercises = enriched.blocks.flatMap(\.exercises)
        XCTAssertEqual(enrichedExercises.map(\.name), [
            "Push Up", "Hammer Curl", "Curl to Press", "Rows"
        ])
        XCTAssertEqual(enrichedExercises.first(where: { $0.name == "Hammer Curl" })?.sets, 4)
        XCTAssertEqual(enrichedExercises.first(where: { $0.name == "Curl to Press" })?.reps, "8")
    }

    func testEditSavePersistsRenamedTitleAndRemovedExercise() async {
        let workout = Workout(
            id: "wk-trim-1",
            name: "Old Title",
            sport: .strength,
            duration: 600,
            intervals: [
                .reps(sets: 3, reps: 10, name: "A", load: nil, restSec: 60, followAlongUrl: nil),
                .reps(sets: 3, reps: 10, name: "B", load: nil, restSec: 60, followAlongUrl: nil),
                .reps(sets: 3, reps: 10, name: "C", load: nil, restSec: 60, followAlongUrl: nil)
            ],
            source: .manual
        )
        mockAPI.saveWorkoutResult = .success(workout)

        var session = EditorV2Session.from(mode: .edit, workout: workout)
        session.title = "New Title"
        if let removeID = session.exercises.first(where: { $0.name == "B" })?.id {
            session.removeExercise(removeID)
        }

        let sut = WorkoutEditorViewModel(workout: workout, dependencies: deps)
        sut.name = session.title
        sut.intervals = session.toSaveIntervals()
        sut.saveBlocks = session.toSocialImportBlocks()
        await sut.save()

        XCTAssertTrue(sut.didSave)
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.name, "New Title")
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.intervals.map(\.name), ["A", "C"])
        XCTAssertEqual(
            mockAPI.lastSaveWorkoutRequest?.blocks?.flatMap(\.exercises).map(\.name),
            ["A", "C"]
        )
    }
}
