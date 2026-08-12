//
//  ActualsCrossSourceDeduperTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2422: certain Strava + Apple Health duplicates collapse to one session.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActualsCrossSourceDeduperTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_775_200_000)

    func testCertainStravaAndAppleHealthCardsMergeOnce() {
        let stravaCard = makeStravaCard(
            id: "strava_99",
            title: "Heavy Leg Day Strength Session",
            start: base,
            durationSeconds: 81 * 60
        )
        let appleCard = ActualsTodayDemoFeed.card(
            from: ActualsHealthKitWorkoutSample(
                id: "hk-1",
                title: "Workout",
                activityType: .strength,
                startDate: base.addingTimeInterval(45),
                durationSeconds: 81 * 60,
                distanceMeters: nil,
                activeEnergyKcal: 612,
                averageHeartRateBPM: 148
            )
        )

        let deduped = ActualsCrossSourceDeduper.dedupeCards([stravaCard, appleCard])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped[0].id, "strava_99")
        XCTAssertEqual(deduped[0].title, "Heavy Leg Day Strength Session")
        XCTAssertEqual(deduped[0].kind, .merged)
        XCTAssertEqual(deduped[0].session?.sourceCount, 2)
        XCTAssertEqual(deduped[0].activity?.avgHR, 148)
        XCTAssertEqual(deduped[0].activity?.calories, 612)
        XCTAssertTrue(deduped[0].sourceLabel.contains("MERGED"))
    }

    func testUncertainOverlapKeepsBothCards() {
        let stravaCard = makeStravaCard(
            id: "strava_1",
            title: "Morning Run",
            start: base,
            durationSeconds: 40 * 60,
            distanceMeters: 8_000
        )
        let appleCard = ActualsTodayDemoFeed.card(
            from: ActualsHealthKitWorkoutSample(
                id: "hk-2",
                title: "Outdoor Run",
                activityType: .run,
                startDate: base.addingTimeInterval(5 * 60),
                durationSeconds: 39 * 60,
                distanceMeters: 7_900,
                activeEnergyKcal: 400,
                averageHeartRateBPM: 150
            )
        )

        let deduped = ActualsCrossSourceDeduper.dedupeCards([stravaCard, appleCard])
        XCTAssertEqual(deduped.count, 2)
    }

    func testCompletionsDedupeDoesNotDoubleCountHours() {
        let strava = WorkoutCompletion(
            id: "strava_42",
            workoutName: "Heavy Leg Day Strength Session",
            startedAt: base,
            endedAt: base.addingTimeInterval(81 * 60),
            durationSeconds: 81 * 60,
            avgHeartRate: nil,
            maxHeartRate: nil,
            activeCalories: nil,
            distanceMeters: nil,
            source: .manual,
            syncedToStrava: true,
            workoutId: nil,
            originalWorkout: nil,
            isSimulated: false
        )
        let apple = WorkoutCompletion(
            id: "applehealth_hk-1",
            workoutName: "Workout",
            startedAt: base.addingTimeInterval(30),
            endedAt: base.addingTimeInterval(81 * 60 + 30),
            durationSeconds: 81 * 60,
            avgHeartRate: 148,
            maxHeartRate: nil,
            activeCalories: 612,
            distanceMeters: nil,
            source: .appleWatch,
            syncedToStrava: false,
            workoutId: nil,
            originalWorkout: nil,
            isSimulated: false
        )

        let deduped = ActualsCrossSourceDeduper.dedupeCompletions([strava, apple])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped[0].durationSeconds, 81 * 60)
        XCTAssertEqual(deduped[0].avgHeartRate, 148)
        XCTAssertEqual(deduped[0].activeCalories, 612)
        XCTAssertTrue(deduped[0].isSyncedToStrava)
        XCTAssertEqual(deduped[0].source, .appleWatch)
        XCTAssertEqual(deduped[0].workoutName, "Heavy Leg Day Strength Session")

        let weekSeconds = deduped.reduce(0) { $0 + $1.durationSeconds }
        XCTAssertEqual(weekSeconds, 81 * 60)
    }

    func testSameProviderDuplicatesAreNotMerged() {
        let a = makeStravaCard(id: "strava_1", title: "A", start: base, durationSeconds: 1800)
        let b = makeStravaCard(
            id: "strava_2",
            title: "B",
            start: base.addingTimeInterval(30),
            durationSeconds: 1800
        )
        XCTAssertEqual(ActualsCrossSourceDeduper.dedupeCards([a, b]).count, 2)
    }

    // MARK: - Helpers

    private func makeStravaCard(
        id: String,
        title: String,
        start: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Double? = nil
    ) -> ActualsTodayDemoCard {
        let activity = ActualsUnmappedActivity(
            title: title,
            provider: .strava,
            startDate: start,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            calories: nil,
            avgHR: nil,
            type: .strength
        )
        let minutes = max(1, Int((durationSeconds / 60).rounded()))
        return ActualsTodayDemoCard(
            id: id,
            kind: .unmapped,
            timeLabel: "08:00",
            title: title,
            stats: [("clock", "\(minutes)m")],
            sourceLabel: "Synced from Strava",
            sourceProvider: .strava,
            session: nil,
            activity: activity,
            fillInSession: nil
        )
    }
}
