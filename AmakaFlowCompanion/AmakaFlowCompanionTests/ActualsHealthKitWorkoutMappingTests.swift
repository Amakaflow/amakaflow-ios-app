//
//  ActualsHealthKitWorkoutMappingTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2419: Apple Health workout samples → Actuals cards / Profile completions.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActualsHealthKitWorkoutMappingTests: XCTestCase {
    func testCardMapsDurationDistanceCaloriesAndHR() {
        let sample = ActualsHealthKitWorkoutSample(
            id: "uuid-1",
            title: "Morning Run",
            activityType: .run,
            startDate: Date(timeIntervalSince1970: 1_775_000_000),
            durationSeconds: 42 * 60,
            distanceMeters: 8_500,
            activeEnergyKcal: 486,
            averageHeartRateBPM: 151
        )
        let card = ActualsTodayDemoFeed.card(from: sample)
        XCTAssertEqual(card.id, "applehealth_uuid-1")
        XCTAssertEqual(card.title, "Morning Run")
        XCTAssertEqual(card.sourceProvider, .appleHealth)
        XCTAssertEqual(card.kind, .unmapped)
        XCTAssertEqual(card.activity?.calories, 486)
        XCTAssertEqual(card.activity?.avgHR, 151)
        XCTAssertTrue(card.stats.contains(where: { $0.value.contains("kcal") }))
        XCTAssertTrue(card.stats.contains(where: { $0.value.contains("bpm") }))
    }

    func testHistoryCardsBucketByLocalDayNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!

        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let morning = ActualsHealthKitWorkoutSample(
            id: "a",
            title: "AM",
            activityType: .strength,
            startDate: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)!,
            durationSeconds: 1800,
            distanceMeters: nil,
            activeEnergyKcal: 200,
            averageHeartRateBPM: nil
        )
        let evening = ActualsHealthKitWorkoutSample(
            id: "b",
            title: "PM",
            activityType: .run,
            startDate: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day)!,
            durationSeconds: 2400,
            distanceMeters: 5_000,
            activeEnergyKcal: 400,
            averageHeartRateBPM: 140
        )

        let groups = ActualsTodayDemoFeed.historyCards(
            from: [morning, evening],
            calendar: calendar,
            now: day
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].cards.map(\.title), ["PM", "AM"])
    }

    func testCompletionsMapForProfileStats() {
        let sample = ActualsHealthKitWorkoutSample(
            id: "uuid-2",
            title: "Strength",
            activityType: .strength,
            startDate: Date(timeIntervalSince1970: 1_775_100_000),
            durationSeconds: 55 * 60,
            distanceMeters: nil,
            activeEnergyKcal: 320,
            averageHeartRateBPM: 120
        )
        let completions = ActualsTodayDemoFeed.completions(from: [sample])
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions[0].id, "applehealth_uuid-2")
        XCTAssertEqual(completions[0].durationSeconds, 55 * 60)
        XCTAssertEqual(completions[0].activeCalories, 320)
        XCTAssertEqual(completions[0].source, .appleWatch)
    }

    func testActivateFromAppleHealthPopulatesFeed() async {
        let samples = [
            ActualsHealthKitWorkoutSample(
                id: "w1",
                title: "Ride",
                activityType: .ride,
                startDate: Date(),
                durationSeconds: 3600,
                distanceMeters: 20_000,
                activeEnergyKcal: 500,
                averageHeartRateBPM: 130
            )
        ]
        let fetcher = MockActualsHealthKitWorkoutFetcher(samples: samples)
        let feed = ActualsTodayDemoFeed(repository: ActualsRepository(database: try! AppDatabase.makeTestDatabase()))
        let sync = ActualsSyncProgressStore()
        await feed.activateFromAppleHealth(sync: sync, fetcher: fetcher)
        XCTAssertTrue(feed.isActive)
        XCTAssertEqual(feed.cards.count, 1)
        XCTAssertEqual(feed.cards.first?.title, "Ride")
        XCTAssertEqual(feed.cards.first?.sourceProvider, .appleHealth)
    }

    func testPromptCompletedUpgradesToGrantedWhenEvidenceQuerySucceeds() async {
        let suite = "ActualsHKUpgrade.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(
            ActualsHealthKitReadAuthorizationState.promptCompleted.rawValue,
            forKey: "ama2387.actuals.appleHealth.authState"
        )
        let fetcher = MockActualsHealthKitWorkoutFetcher(samples: [])
        let connector = LiveActualsHealthKitConnector(
            defaults: defaults,
            workoutFetcher: fetcher
        )
        let outcome = await connector.connect()
        XCTAssertEqual(outcome, .granted)
        XCTAssertEqual(connector.authorizationState, .authorized)
        defaults.removePersistentDomain(forName: suite)
    }

    func testPromptCompletedNeedsSettingsWhenEvidenceQueryFails() async {
        struct Boom: Error {}
        let suite = "ActualsHKUpgradeFail.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(
            ActualsHealthKitReadAuthorizationState.promptCompleted.rawValue,
            forKey: "ama2387.actuals.appleHealth.authState"
        )
        let fetcher = MockActualsHealthKitWorkoutFetcher(error: Boom())
        let connector = LiveActualsHealthKitConnector(
            defaults: defaults,
            workoutFetcher: fetcher
        )
        let store = ActualsSourceConnectionStore(defaults: defaults)
        let outcome = await connector.connect()
        ActualsAppleHealthConnectAction.apply(
            outcome: outcome,
            store: store,
            openSettings: { connector.openHealthSettings() }
        )
        XCTAssertEqual(outcome, .needsSettings)
        XCTAssertFalse(store.isConnected(.appleHealth))
        defaults.removePersistentDomain(forName: suite)
    }
}
