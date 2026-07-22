//
//  WorkoutStartSelectionTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2291: Start sheet device defaults + Library detail routing by source.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutStartSelectionTests: XCTestCase {

    func testPreferredDeviceIsGarminWhenPaired() {
        XCTAssertEqual(
            WorkoutStartDefaults.preferredDevice(garminPaired: true),
            .garmin
        )
    }

    func testPreferredDeviceIsPhoneWhenGarminNotPaired() {
        XCTAssertEqual(
            WorkoutStartDefaults.preferredDevice(garminPaired: false),
            .phone
        )
    }

    func testGarminRowNeedsPairingWhenUnpaired() {
        XCTAssertEqual(
            WorkoutStartDefaults.garminRowMode(garminPaired: false),
            .needsPairing
        )
        XCTAssertEqual(
            WorkoutStartDefaults.garminRowMode(garminPaired: true),
            .push
        )
    }

    func testAppleIsNeverSilentDefault() {
        // Even when Watch is reachable, unpaired Garmin still defaults to Phone.
        // Apple remains a labeled "try" path on the sheet.
        XCTAssertEqual(
            WorkoutStartDefaults.preferredDevice(garminPaired: false),
            .phone
        )
        XCTAssertEqual(
            WorkoutStartDefaults.appleAvailabilityLabel(watchReachable: true),
            "Try"
        )
        XCTAssertTrue(
            WorkoutStartDefaults.appleAvailabilityLabel(watchReachable: false)
                .localizedCaseInsensitiveContains("try")
        )
    }

    func testHandoffResolverMapsDevices() {
        XCTAssertEqual(WorkoutStartHandoffResolver.handoff(for: .garmin), .garmin)
        XCTAssertEqual(WorkoutStartHandoffResolver.handoff(for: .apple), .apple)
        XCTAssertEqual(WorkoutStartHandoffResolver.handoff(for: .phone), .phone)
    }

    func testAmazfitNotInStartDeviceCases() {
        let rawValues = WorkoutStartDevice.allCases.map(\.rawValue)
        XCTAssertFalse(rawValues.contains("amazfit"))
        XCTAssertEqual(Set(rawValues), Set(["garmin", "apple", "phone"]))
    }
}

@MainActor
final class LibraryDetailRoutingTests: XCTestCase {

    func testWorkoutIDRoutesToUnifiedDetail() {
        let destination = LibraryDetailRouting.destination(forWorkoutID: "w-1")
        XCTAssertEqual(destination, .unifiedWorkout(workoutID: "w-1"))
    }

    func testKnowledgeWorkoutRoutesToUnifiedDetail() {
        let withMatch = LibraryDetailRouting.destination(
            forKnowledgeKind: .workout,
            itemID: "lib-1",
            matchingWorkoutID: "w-ig"
        )
        XCTAssertEqual(withMatch, .unifiedWorkout(workoutID: "w-ig"))

        let withoutMatch = LibraryDetailRouting.destination(
            forKnowledgeKind: .workout,
            itemID: "lib-workout",
            matchingWorkoutID: nil
        )
        XCTAssertEqual(withoutMatch, .unifiedWorkout(workoutID: "lib-workout"))
    }

    func testNonWorkoutKnowledgeKeepsLibraryDetail() {
        XCTAssertEqual(
            LibraryDetailRouting.destination(
                forKnowledgeKind: .article,
                itemID: "a-1",
                matchingWorkoutID: nil
            ),
            .knowledgeDetail(itemID: "a-1")
        )
        XCTAssertEqual(
            LibraryDetailRouting.destination(
                forKnowledgeKind: .video,
                itemID: "v-1",
                matchingWorkoutID: nil
            ),
            .knowledgeDetail(itemID: "v-1")
        )
        XCTAssertEqual(
            LibraryDetailRouting.destination(
                forKnowledgeKind: .plan,
                itemID: "p-1",
                matchingWorkoutID: nil
            ),
            .knowledgeDetail(itemID: "p-1")
        )
    }

    func testSocialSourcesShowCreditRow() {
        XCTAssertTrue(LibraryDetailRouting.showsSocialCreditRow(source: .instagram))
        XCTAssertTrue(LibraryDetailRouting.showsSocialCreditRow(source: .tiktok))
        XCTAssertTrue(LibraryDetailRouting.showsSocialCreditRow(source: .youtube))
        XCTAssertFalse(LibraryDetailRouting.showsSocialCreditRow(source: .manual))
        XCTAssertFalse(LibraryDetailRouting.showsSocialCreditRow(source: .coach))
    }

    func testLibraryListEntryDestinationMatchesSource() {
        let ig = Workout(
            id: "ig-1",
            name: "IG Push",
            sport: .strength,
            duration: 1800,
            intervals: [],
            source: .instagram,
            sourceUrl: "https://instagram.com/reel/x"
        )
        let manual = Workout(
            id: "man-1",
            name: "Manual Lift",
            sport: .strength,
            duration: 1200,
            intervals: [],
            source: .manual
        )

        XCTAssertEqual(
            LibraryListEntry.workout(ig).destination,
            .unifiedWorkout(workoutID: "ig-1")
        )
        XCTAssertEqual(
            LibraryListEntry.workout(manual).destination,
            .unifiedWorkout(workoutID: "man-1")
        )
    }

    func testMergedEntriesPutsWorkoutsAndKnowledgeOnSameList() {
        let workouts = [
            Workout(id: "w1", name: "IG", sport: .strength, duration: 1, intervals: [], source: .instagram),
            Workout(id: "w2", name: "Manual", sport: .strength, duration: 1, intervals: [], source: .manual)
        ]
        let knowledge = [
            Components.Schemas.LibraryItem(
                bookmarked: false,
                id: "article-1",
                kind: .article,
                savedAt: "2026-07-13T00:00:00Z",
                sourceDomain: "example.com",
                sourceUrl: "https://example.com",
                tags: ["endurance"],
                thumbnailUrl: nil,
                title: "Article"
            )
        ]

        let entries = LibraryViewModel.mergedEntries(
            workouts: workouts,
            knowledge: knowledge,
            selectedKinds: [],
            selectedTag: nil
        )

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].id, "workout:w1")
        XCTAssertEqual(entries[1].id, "workout:w2")
        XCTAssertEqual(entries[2].id, "knowledge:article-1")
    }

    func testMergedEntriesWorkoutKindFilterHidesKnowledgeNonWorkouts() {
        let workouts = [
            Workout(id: "w1", name: "Manual", sport: .strength, duration: 1, intervals: [], source: .manual)
        ]
        let knowledge = [
            Components.Schemas.LibraryItem(
                bookmarked: false,
                id: "video-1",
                kind: .video,
                savedAt: "2026-07-13T00:00:00Z",
                sourceDomain: "youtube.com",
                sourceUrl: nil,
                tags: nil,
                thumbnailUrl: nil,
                title: "Video"
            )
        ]

        let entries = LibraryViewModel.mergedEntries(
            workouts: workouts,
            knowledge: knowledge,
            selectedKinds: [.workout],
            selectedTag: nil
        )

        XCTAssertEqual(entries.map(\.id), ["workout:w1"])
    }
}

@MainActor
final class LibraryViewModelWorkoutMergeTests: XCTestCase {
    private var api: MockAPIService!
    private var viewModel: LibraryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
        viewModel = LibraryViewModel(apiService: api)
    }

    override func tearDown() async throws {
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testLoadMergesWorkoutsAndRoutesSocialOrManualToUnifiedDetail() async {
        api.listLibraryItemsResult = .success(
            Components.Schemas.LibraryItemList(
                items: [
                    Components.Schemas.LibraryItem(
                        bookmarked: false,
                        id: "article-1",
                        kind: .article,
                        savedAt: "2026-07-13T00:00:00Z",
                        sourceDomain: "example.com",
                        sourceUrl: "https://example.com",
                        tags: nil,
                        thumbnailUrl: nil,
                        title: "Article"
                    )
                ],
                total: 1
            )
        )
        api.fetchWorkoutsResult = .success([
            Workout(
                id: "ig-1",
                name: "IG Day",
                sport: .strength,
                duration: 1800,
                intervals: [],
                source: .instagram,
                sourceUrl: "https://instagram.com/reel/abc"
            ),
            Workout(
                id: "man-1",
                name: "Manual Day",
                sport: .strength,
                duration: 1200,
                intervals: [],
                source: .manual
            )
        ])

        await viewModel.load()

        XCTAssertTrue(api.fetchWorkoutsCalled)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.entries.count, 3)

        let igDestination = viewModel.entries[0].destination
        let manualDestination = viewModel.entries[1].destination
        XCTAssertEqual(igDestination, .unifiedWorkout(workoutID: "ig-1"))
        XCTAssertEqual(manualDestination, .unifiedWorkout(workoutID: "man-1"))

        let resolvedIG = viewModel.resolveWorkout(for: igDestination)
        XCTAssertEqual(resolvedIG?.source, .instagram)
        XCTAssertEqual(resolvedIG?.sourceUrl, "https://instagram.com/reel/abc")

        let resolvedManual = viewModel.resolveWorkout(for: manualDestination)
        XCTAssertEqual(resolvedManual?.source, .manual)
    }
}
