//
//  StravaActivityClassificationTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2411 — generic Workout title heuristics + elliptical/HIIT defaults.
//

import XCTest
@testable import AmakaFlowCompanion

final class StravaActivityClassificationTests: XCTestCase {

    func testSkiRowWorkoutIsNotStrength() {
        let type = StravaActivityClassification.actualsWorkoutType(
            sportType: "Workout",
            title: "Ski Row"
        )
        XCTAssertNotEqual(type, .strength)
        XCTAssertEqual(type, .other)
        XCTAssertEqual(
            StravaActivityClassification.typeIcon(sportType: "Workout", title: "Ski Row"),
            "figure.mixed.cardio"
        )
    }

    func testAssaultBikeWorkoutIsNotStrength() {
        let type = StravaActivityClassification.actualsWorkoutType(
            sportType: "Workout",
            title: "Assault bike"
        )
        XCTAssertNotEqual(type, .strength)
        XCTAssertEqual(type, .other)
        XCTAssertEqual(
            StravaActivityClassification.typeIcon(sportType: "Workout", title: "Assault bike"),
            "figure.mixed.cardio"
        )
    }

    func testPlainUpperBodyWorkoutRemainsStrength() {
        let type = StravaActivityClassification.actualsWorkoutType(
            sportType: "Workout",
            title: "Upper Body"
        )
        XCTAssertEqual(type, .strength)
        XCTAssertEqual(
            StravaActivityClassification.typeIcon(sportType: "Workout", title: "Upper Body"),
            "figure.strengthtraining.traditional"
        )
    }

    func testEllipticalTypeIsNotStrength() {
        let type = StravaActivityClassification.actualsWorkoutType(
            sportType: "Elliptical",
            title: "Morning elliptical"
        )
        XCTAssertNotEqual(type, .strength)
        XCTAssertEqual(type, .other)
        XCTAssertEqual(
            StravaActivityClassification.typeIcon(sportType: "Elliptical", title: "Morning elliptical"),
            "figure.elliptical"
        )
    }

    func testHIITTypeIsNotStrength() {
        XCTAssertEqual(
            StravaActivityClassification.actualsWorkoutType(
                sportType: "HighIntensityIntervalTraining",
                title: "Intervals"
            ),
            .other
        )
    }

    func testWeightTrainingAndCrossFitStayStrength() {
        XCTAssertEqual(
            StravaActivityClassification.actualsWorkoutType(
                sportType: "WeightTraining",
                title: "Ski Row"
            ),
            .strength
        )
        XCTAssertEqual(
            StravaActivityClassification.actualsWorkoutType(
                sportType: "CrossFit",
                title: "Assault bike metcon"
            ),
            .strength
        )
    }

    func testBarbellRowTitleDoesNotFlipWorkoutToCardio() {
        XCTAssertEqual(
            StravaActivityClassification.actualsWorkoutType(
                sportType: "Workout",
                title: "Barbell Row Day"
            ),
            .strength
        )
    }

    func testFeedCardUsesTitleHeuristic() {
        let skiRow = StravaCompletedActivityDTO(
            stravaId: 11,
            name: "Ski Row",
            type: "Workout",
            distanceKm: 0,
            durationMin: 40,
            startDate: "2026-08-11T15:00:00Z",
            startDateLocal: "2026-08-11T10:00:00",
            description: ""
        )
        let upper = StravaCompletedActivityDTO(
            stravaId: 12,
            name: "Upper Body",
            type: "Workout",
            distanceKm: 0,
            durationMin: 45,
            startDate: "2026-08-11T17:00:00Z",
            startDateLocal: "2026-08-11T12:00:00",
            description: ""
        )
        let now = ISO8601DateFormatter().date(from: "2026-08-11T18:00:00Z")!
        let cards = ActualsTodayDemoFeed.cards(from: [skiRow, upper], now: now)
        let skiCard = cards.first { $0.id == "strava_11" }
        let upperCard = cards.first { $0.id == "strava_12" }
        XCTAssertEqual(skiCard?.activity?.type, .other)
        XCTAssertEqual(upperCard?.activity?.type, .strength)
    }
}
