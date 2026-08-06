//
//  BuilderV3Tests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2372 — Builder v3 type-registry seeds + run→blocks serialization.
//

import XCTest
@testable import AmakaFlowCompanion

final class BuilderV3Tests: XCTestCase {

    // MARK: - Category coverage

    func testEveryCategoryHasExpectedSeedCount() {
        XCTAssertEqual(BuilderV3TypeRegistry.seeds(for: .lift).count, 6)
        XCTAssertEqual(BuilderV3TypeRegistry.seeds(for: .conditioning).count, 5)
        XCTAssertEqual(BuilderV3TypeRegistry.seeds(for: .run).count, 4)
        XCTAssertEqual(BuilderV3TypeRegistry.seeds(for: .recover).count, 2)
        XCTAssertEqual(BuilderV3TypeRegistry.all.count, 17)
    }

    func testEverySeedHasAUniqueBuilderV3AccessibilityId() {
        let ids = BuilderV3TypeRegistry.all.map(\.accessibilityId)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertTrue(id.hasPrefix("builder_v3_type_"), "\(id) missing builder_v3_ prefix")
        }
    }

    // MARK: - Lift seeds → EditorV2Session

    func testStraightSetsSeedIsBlankSession() {
        let session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.straightSets)
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertNil(session.formatGroupKey)
    }

    func testSupersetSeedPinsSupersetFormat() {
        let session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.superset)
        XCTAssertEqual(session.formatGroupKey, "fmt")
        XCTAssertEqual(session.groups["fmt"]?.type, .superset)
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertEqual(session.title, "Supersets")
    }

    func testSeedDefaultTitlesMatchMockupCanvas() {
        let untitled: [BuilderV3TypeSeed] = [
            BuilderV3TypeRegistry.straightSets,
            BuilderV3TypeRegistry.blank
        ]
        for seed in untitled {
            XCTAssertNil(seed.defaultTitle, seed.id)
            if BuilderV3TypeRegistry.isRunSeed(seed) {
                XCTAssertEqual(BuilderV3RunRegistry.makeRunSession(for: seed).title, "")
            } else {
                XCTAssertEqual(BuilderV3TypeRegistry.makeEditorSession(for: seed).title, "")
            }
        }

        let titledCases: [(BuilderV3TypeSeed, String)] = BuilderV3TypeRegistry.all.compactMap { seed in
            guard let title = seed.defaultTitle else { return nil }
            return (seed, title)
        }
        XCTAssertEqual(titledCases.count, BuilderV3TypeRegistry.all.count - untitled.count)

        for (seed, expectedTitle) in titledCases {
            if BuilderV3TypeRegistry.isRunSeed(seed) {
                XCTAssertEqual(
                    BuilderV3RunRegistry.makeRunSession(for: seed).title,
                    expectedTitle,
                    seed.id
                )
            } else {
                XCTAssertEqual(
                    BuilderV3TypeRegistry.makeEditorSession(for: seed).title,
                    expectedTitle,
                    seed.id
                )
            }
        }
    }

    func testRunInstructionCopyBlankVsSeeded() {
        XCTAssertEqual(
            BuilderV3RunInstructionCopy.line(isBlankDraft: true),
            "JUST ADD STEPS — STRUCTURE COMES LATER"
        )
        XCTAssertEqual(
            BuilderV3RunInstructionCopy.line(isBlankDraft: false),
            "DEFAULTS APPLIED — TAP ANYTHING TO TWEAK"
        )
        let seeded = BuilderV3RunRegistry.makeRunSession(for: BuilderV3TypeRegistry.intervals)
        XCTAssertFalse(seeded.isBlankDraft)
        var cleared = seeded
        while let first = cleared.blocks.first {
            cleared.removeBlock(first.id)
        }
        XCTAssertTrue(cleared.isBlankDraft)
    }

    func testPushSeedSeedsFixedStarterNamesWithDefaultPrescription() {
        let session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.push)
        XCTAssertEqual(session.exercises.map(\.name), ["Bench Press", "Overhead Press", "Triceps Pushdown"])
        for exercise in session.exercises {
            XCTAssertEqual(exercise.sets, 3)
            XCTAssertEqual(exercise.reps, 10)
            XCTAssertEqual(exercise.restSeconds, 60)
            XCTAssertNil(exercise.groupKey)
        }
    }

    func testPullLegsFullBodySeedsUseFixedStarters() {
        XCTAssertEqual(
            BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.pull).exercises.map(\.name),
            ["Deadlift", "Barbell Row", "Lat Pulldown"]
        )
        XCTAssertEqual(
            BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.legs).exercises.map(\.name),
            ["Back Squat", "Romanian Deadlift", "Leg Press"]
        )
        XCTAssertEqual(
            BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.fullBody).exercises.map(\.name),
            ["Squat", "Bench Press", "Barbell Row"]
        )
    }

    // MARK: - Conditioning seeds → format chips

    func testConditioningSeedsPinExpectedFormat() {
        let cases: [(BuilderV3TypeSeed, EditorV2GroupType)] = [
            (BuilderV3TypeRegistry.emom, .emom),
            (BuilderV3TypeRegistry.amrap, .amrap),
            (BuilderV3TypeRegistry.tabata, .tabata),
            (BuilderV3TypeRegistry.forTime, .fortime),
            (BuilderV3TypeRegistry.circuit, .circuit)
        ]
        for (seed, expected) in cases {
            let session = BuilderV3TypeRegistry.makeEditorSession(for: seed)
            XCTAssertEqual(session.groups["fmt"]?.type, expected, "\(seed.id) should pin \(expected)")
            XCTAssertEqual(session.formatGroupKey, "fmt")
        }
    }

    // MARK: - Recover seeds

    func testMobilitySeedIsPlainDurationNotRunHolds() {
        let session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.mobility)
        XCTAssertEqual(session.exercises.count, 3)
        for exercise in session.exercises {
            XCTAssertEqual(exercise.durationSeconds, 30)
            XCTAssertNil(exercise.distanceMeters, "mobility rows are plain duration, not run holds")
            XCTAssertNil(exercise.sets)
            XCTAssertNil(exercise.reps)
            XCTAssertNil(exercise.groupKey)
        }
    }

    func testBlankSeedIsCompletelyEmpty() {
        let session = BuilderV3TypeRegistry.makeEditorSession(for: BuilderV3TypeRegistry.blank)
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertNil(session.formatGroupKey)
    }

    // MARK: - Run seeds → BuilderV3RunSession

    func testIntervalsSeedBuildsWarmupRepeatBlockCooldown() {
        let session = BuilderV3RunRegistry.makeRunSession(for: BuilderV3TypeRegistry.intervals)
        XCTAssertEqual(session.blocks.count, 3)
        XCTAssertEqual(session.blocks[0].steps.first?.kind, .warmup)
        XCTAssertEqual(session.blocks[1].repeatCount, 6)
        XCTAssertEqual(session.blocks[1].steps.map(\.kind), [.work, .recover])
        XCTAssertEqual(session.blocks[1].steps.first?.distanceMeters, 400)
        XCTAssertEqual(session.blocks[2].steps.first?.kind, .cooldown)
    }

    func testTempoSeedIsSingleContinuousWorkBlock() {
        let session = BuilderV3RunRegistry.makeRunSession(for: BuilderV3TypeRegistry.tempo)
        XCTAssertEqual(session.blocks.count, 3)
        XCTAssertFalse(session.blocks[1].isRepeatBlock)
        XCTAssertEqual(session.blocks[1].steps.first?.durationSeconds, 1200)
    }

    func testLongRunSeedIsDistanceBased() {
        let session = BuilderV3RunRegistry.makeRunSession(for: BuilderV3TypeRegistry.longRun)
        XCTAssertEqual(session.blocks[1].steps.first?.distanceMeters, 10000)
    }

    func testRacePaceSeedRepeatsAtRacePace() {
        let session = BuilderV3RunRegistry.makeRunSession(for: BuilderV3TypeRegistry.racePace)
        XCTAssertEqual(session.blocks[1].repeatCount, 4)
        XCTAssertEqual(session.blocks[1].steps.first?.paceTarget, "race pace")
    }

    // MARK: - Run → SocialImportBlock serialization (mapper path unchanged)

    func testRepeatBlockSerializesAsCircuitWithRoundsAndTwoExercises() {
        var session = BuilderV3RunSession()
        session.addRepeatBlock(
            repeatCount: 6,
            work: BuilderV3RunStep(kind: .work, name: "400 m", distanceMeters: 400, paceTarget: "5K pace"),
            recover: BuilderV3RunStep(kind: .recover, name: "Recover", durationSeconds: 90)
        )
        let blocks = session.toSocialImportBlocks()
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, "circuit")
        XCTAssertEqual(blocks[0].rounds, 6)
        XCTAssertEqual(blocks[0].exercises.count, 2)
        XCTAssertEqual(blocks[0].exercises[0].name, "400 m")
        XCTAssertEqual(blocks[0].exercises[0].distanceMeters, 400)
        XCTAssertEqual(blocks[0].exercises[1].seconds, 90)
        XCTAssertEqual(blocks[0].structureSource, "user_confirmed")
    }

    func testWarmupAndCooldownSerializeAsSingleRoundSoftSections() {
        var session = BuilderV3RunSession()
        session.addWarmup(name: "Easy jog", durationSeconds: 600)
        session.addCooldown(name: "Walk", durationSeconds: 300)
        let blocks = session.toSocialImportBlocks()
        XCTAssertEqual(blocks[0].type, "warmup")
        XCTAssertEqual(blocks[0].rounds, 1)
        XCTAssertEqual(blocks[0].exercises.first?.seconds, 600)
        XCTAssertEqual(blocks[1].type, "cooldown")
        XCTAssertEqual(blocks[1].exercises.first?.seconds, 300)
    }

    func testStandaloneWorkSerializesAsSetsBlock() {
        var session = BuilderV3RunSession()
        session.addStandaloneWork(name: "Tempo run", durationSeconds: 1200, paceTarget: "comfortably hard")
        let blocks = session.toSocialImportBlocks()
        XCTAssertEqual(blocks[0].type, "sets")
        XCTAssertEqual(blocks[0].rounds, 1)
        XCTAssertEqual(blocks[0].exercises.first?.load, "comfortably hard")
    }

    func testRunSessionToSaveIntervalsFlattensAllSteps() {
        var session = BuilderV3RunSession()
        session.addWarmup(durationSeconds: 600)
        session.addRepeatBlock(
            repeatCount: 4,
            work: BuilderV3RunStep(kind: .work, name: "1000 m", distanceMeters: 1000),
            recover: BuilderV3RunStep(kind: .recover, name: "Recover", durationSeconds: 120)
        )
        let intervals = session.toSaveIntervals()
        XCTAssertEqual(intervals.map(\.type), ["warmup", "distance", "time"])
        XCTAssertEqual(intervals[1].meters, 1000)
        XCTAssertEqual(intervals[2].seconds, 120)
    }

    func testMoveBlockReordersWithoutLosingBlocks() {
        var session = BuilderV3RunSession()
        session.addWarmup()
        session.addStandaloneWork(name: "Work", durationSeconds: 600)
        session.addCooldown()
        session.moveBlock(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(session.blocks.map(\.timelineLabel), ["Cool-down walk", "Warm-up jog", "Work"])
    }

    // MARK: - Gym overlay (mark, never hide)

    func testGymOverlayFlattensAvailableEquipmentAcrossCategories() {
        let keys = BuilderV3GymOverlay.availableEquipmentKeys(
            bodyweight: ["pull_up_bar": true, "rings": false],
            cardio: ["rower": true],
            strength: ["barbell": true, "dumbbells": false],
            mobility: nil
        )
        XCTAssertEqual(keys, Set(["pull_up_bar", "rower", "barbell"]))
    }

    func testGymOverlayBodyweightAlwaysInGym() {
        XCTAssertTrue(BuilderV3GymOverlay.isInGym(equipmentKey: nil, availableKeys: Set(["barbell"])))
    }

    func testGymOverlayNoProfileNeverMarksMissing() {
        XCTAssertTrue(BuilderV3GymOverlay.isInGym(equipmentKey: "barbell", availableKeys: nil))
    }

    func testGymOverlayMarksMissingWhenEquipmentAbsentFromProfile() {
        XCTAssertFalse(BuilderV3GymOverlay.isInGym(equipmentKey: "barbell", availableKeys: Set(["dumbbells"])))
        XCTAssertTrue(BuilderV3GymOverlay.isInGym(equipmentKey: "dumbbells", availableKeys: Set(["dumbbells"])))
    }

    // MARK: - Exercise library + search fixture fallback

    func testExerciseLibraryMatchesNameOrMuscle() {
        XCTAssertTrue(BuilderV3ExerciseLibrary.demo.contains { BuilderV3ExerciseLibrary.matches($0, query: "bench") })
        XCTAssertTrue(BuilderV3ExerciseLibrary.demo.contains { BuilderV3ExerciseLibrary.matches($0, query: "quads") })
        XCTAssertFalse(BuilderV3ExerciseLibrary.demo.contains { BuilderV3ExerciseLibrary.matches($0, query: "zzz-no-match") })
    }

    func testSearchClientFixtureFallbackFiltersByQuery() {
        let results = BuilderV3ExerciseSearchClient.fixtureResults(matching: "squat")
        XCTAssertTrue(results.contains { $0.name == "Back Squat" })
        XCTAssertTrue(results.contains { $0.name == "Goblet Squat" })
        XCTAssertFalse(results.contains { $0.name == "Bench Press" })
    }

    func testSearchClientFixtureFallbackEmptyQueryReturnsFullCatalog() {
        XCTAssertEqual(
            BuilderV3ExerciseSearchClient.fixtureResults(matching: "").count,
            BuilderV3ExerciseLibrary.demo.count
        )
    }

    func testBrowseCategoryUsesPinnedWireValues() {
        XCTAssertEqual(BuilderV3BrowseCategory.strength.queryValue, "strength")
        XCTAssertEqual(BuilderV3BrowseCategory.cardio.queryValue, "cardio")
        XCTAssertEqual(BuilderV3BrowseCategory.plyometrics.queryValue, "plyometric")
    }

    func testCoreStrengthChipUsesCatalogAbsKey() {
        let coreChip = BuilderV3ExerciseLibrary.strengthMuscleChips.first { $0.label == "Core" }
        XCTAssertEqual(coreChip?.key, "abs")
    }

    func testDemoCatalogHasStableIdsAndRequiredCardio() {
        XCTAssertEqual(Set(BuilderV3ExerciseLibrary.demo.map(\.id)).count, BuilderV3ExerciseLibrary.demo.count)
        XCTAssertFalse(BuilderV3ExerciseLibrary.demo.contains { UUID(uuidString: $0.id) != nil })
        XCTAssertTrue(BuilderV3ExerciseLibrary.demo.contains { $0.name == "Ski Erg" })
        XCTAssertTrue(BuilderV3ExerciseLibrary.demo.contains { $0.name == "Treadmill Run" })
    }

    func testLiveEmptySearchDoesNotFallBackToFixture() async {
        MockURLProtocol.reset()
        MockURLProtocol.setResponse(
            data: #"{"results":[],"count":0,"query":"no-match"}"#.data(using: .utf8)!
        )
        let client = BuilderV3ExerciseSearchClient(
            apiService: APIService(session: MockURLProtocol.mockSession()),
            useFixtures: false
        )

        let result = await client.search(query: "no-match", limit: 30)

        XCTAssertEqual(result.mode, .live)
        XCTAssertTrue(result.items.isEmpty)
        MockURLProtocol.reset()
    }

    func testUpstreamFailureUsesMockFixtureWithCardio() async {
        MockURLProtocol.reset()
        MockURLProtocol.setError(MockNetworkError.noConnection)
        let client = BuilderV3ExerciseSearchClient(
            apiService: APIService(session: MockURLProtocol.mockSession()),
            useFixtures: false
        )

        let result = await client.list(
            category: "cardio",
            muscle: nil,
            equipment: nil,
            limit: 40,
            offset: 0
        )

        XCTAssertEqual(result.mode, .mock)
        XCTAssertTrue(result.items.contains { $0.name == "Ski Erg" })
        MockURLProtocol.reset()
    }

    func testListSendsCategoryAndChipQueryParameters() async {
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let query = Dictionary(
                uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
                    item.value.map { (item.name, $0) }
                }
            )
            XCTAssertEqual(request.url?.path, "/v1/exercises")
            XCTAssertEqual(query["category"], "strength")
            XCTAssertEqual(query["muscle"], "quadriceps")
            XCTAssertNil(query["equipment"])
            XCTAssertEqual(query["limit"], "40")
            XCTAssertEqual(query["offset"], "40")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, #"{"exercises":[],"count":0}"#.data(using: .utf8)!)
        }
        let client = BuilderV3ExerciseSearchClient(
            apiService: APIService(session: MockURLProtocol.mockSession()),
            useFixtures: false
        )

        let result = await client.list(
            category: "strength",
            muscle: "quadriceps",
            equipment: nil,
            limit: 40,
            offset: 40
        )

        XCTAssertEqual(result.mode, .live)
        XCTAssertTrue(result.items.isEmpty)
        MockURLProtocol.reset()
    }
}
