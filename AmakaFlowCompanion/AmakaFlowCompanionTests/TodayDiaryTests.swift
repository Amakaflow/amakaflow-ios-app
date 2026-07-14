//
//  TodayDiaryTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2289: Today completed diary — filter, empty, immutability, verify/map/enrich.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class TodayDiaryTests: XCTestCase {

    private var calendar: Calendar!
    private var now: Date!

    override func setUp() async throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 15, minute: 0))!
    }

    // MARK: - Today filter

    func testCompletionsForTodayKeepsOnlySameDayNewestFirst() {
        let garmin = makeCompletion(id: "g", startedOffset: -3600, source: .garmin)
        let phone = makeCompletion(id: "p", startedOffset: -7200, source: .phone)
        let yesterday = makeCompletion(id: "y", startedOffset: -86400 - 3600, source: .appleWatch)

        let result = TodayDiary.completionsForToday(
            [yesterday, phone, garmin],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.id), ["g", "p"])
        XCTAssertEqual(result.first?.source, .garmin)
    }

    func testCompletionsForTodayEmptyWhenNothingSynced() {
        let yesterday = makeCompletion(id: "y", startedOffset: -86400, source: .garmin)
        let result = TodayDiary.completionsForToday([yesterday], now: now, calendar: calendar)
        XCTAssertTrue(result.isEmpty)
    }

    func testViewModelTodaysCompletionsUsesDiaryHelper() async {
        let mockAPI = MockAPIService()
        let mockPairing = MockPairingService()
        mockPairing.configurePaired()
        mockAPI.fetchCompletionsResult = .success([
            makeCompletion(id: "g", startedOffset: -1800, source: .garmin),
            makeCompletion(id: "old", startedOffset: -86400 * 2, source: .phone)
        ])

        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let fixedNow = now!
        let vm = ActivityHistoryViewModel(
            dependencies: deps,
            nowProvider: { fixedNow },
            calendar: calendar
        )

        await vm.loadCompletions()

        XCTAssertEqual(vm.todaysCompletions.map(\.id), ["g"])
        XCTAssertEqual(vm.completions.count, 2)
    }

    // MARK: - Structure edit blocked

    func testCompletedItemCannotOpenStructureEdit() {
        XCTAssertFalse(TodayDiary.allowsStructureEdit)
        XCTAssertEqual(TodayDiary.allowsStructureEdit, false)

        // Pure contract: completed diary UI must not surface structure Edit.
        // (UI identifier `af_completion_edit_structure` / "Edit Workout" are absent
        // from CompletionDetailView after AMA-2289 — covered by Maestro.)
        let actions = TodayDiary.diaryActions.map(\.title)
        XCTAssertFalse(actions.contains("Edit"))
        XCTAssertFalse(actions.contains(where: { $0.lowercased().contains("edit") }))
    }

    // MARK: - Verify / map / enrich entry points

    func testDiaryActionsExposeVerifyMapEnrich() {
        XCTAssertEqual(
            TodayDiary.diaryActions.map(\.rawValue),
            ["verify", "map", "enrich"]
        )
        XCTAssertEqual(TodayDiary.CompletedItemAction.verify.accessibilityIdentifier, "af_completion_action_verify")
        XCTAssertEqual(TodayDiary.CompletedItemAction.map.accessibilityIdentifier, "af_completion_action_map")
        XCTAssertEqual(TodayDiary.CompletedItemAction.enrich.accessibilityIdentifier, "af_completion_action_enrich")
    }

    func testVerifyMarksCompletionWithoutStructureEdit() async {
        let mockAPI = MockAPIService()
        let mockPairing = MockPairingService()
        mockPairing.configurePaired()
        mockAPI.fetchCompletionDetailResult = .success(WorkoutCompletionDetail.garminTodaySample)

        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = CompletionDetailViewModel(completionId: "today-garmin-run", dependencies: deps)
        await vm.loadDetail()

        XCTAssertFalse(vm.isVerified)
        vm.performDiaryAction(.verify)
        XCTAssertTrue(vm.isVerified)
        XCTAssertTrue(vm.showDiaryActionToast)
        XCTAssertFalse(vm.allowsStructureEdit)
    }

    func testMapAndEnrichOpenSheets() {
        let mockAPI = MockAPIService()
        let mockPairing = MockPairingService()
        mockPairing.configurePaired()
        let deps = AppDependencies(
            apiService: mockAPI,
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let vm = CompletionDetailViewModel(completionId: "today-phone-strength", dependencies: deps)

        vm.performDiaryAction(.map)
        XCTAssertTrue(vm.showingMapSheet)

        vm.performDiaryAction(.enrich)
        XCTAssertTrue(vm.showingEnrichSheet)

        vm.enrichNote = "Felt strong"
        vm.saveEnrichNote()
        XCTAssertFalse(vm.showingEnrichSheet)
        XCTAssertTrue(vm.showDiaryActionToast)
        XCTAssertTrue(vm.diaryActionToastMessage.contains("structure unchanged"))
    }

    func testTodayDiarySampleIncludesGarminAndPhoneWithoutManualEntry() {
        let diary = WorkoutCompletion.todayDiarySampleData(now: now)
        XCTAssertEqual(diary.count, 2)
        XCTAssertEqual(diary.map(\.source), [.garmin, .phone])
        XCTAssertTrue(diary.allSatisfy { calendar.isDate($0.startedAt, inSameDayAs: now) })
        let filtered = TodayDiary.completionsForToday(diary, now: now, calendar: calendar)
        XCTAssertEqual(filtered.map(\.id), ["today-garmin-run", "today-phone-strength"])
    }

    // MARK: - Helpers

    private func makeCompletion(
        id: String,
        startedOffset: TimeInterval,
        source: WorkoutCompletion.CompletionSource
    ) -> WorkoutCompletion {
        let started = now.addingTimeInterval(startedOffset)
        return WorkoutCompletion(
            id: id,
            workoutName: "Test \(id)",
            startedAt: started,
            endedAt: started.addingTimeInterval(1800),
            durationSeconds: 1800,
            avgHeartRate: 120,
            maxHeartRate: 150,
            activeCalories: 200,
            distanceMeters: source == .garmin ? 5000 : nil,
            source: source,
            syncedToStrava: false,
            workoutId: nil,
            originalWorkout: nil,
            isSimulated: true
        )
    }
}
