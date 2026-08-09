//
//  ActualsPlanMatcherTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: map-to-plan scoring + WHY lines + keep-as-is copy/IDs.
//

import XCTest
@testable import AmakaFlowCompanion

final class ActualsPlanMatcherTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    func testBestMatchPrefersSameStartAndDistance() {
        let activity = ActualsUnmappedActivity(
            title: "Lunch Run",
            provider: .strava,
            startDate: noon,
            durationSeconds: 59 * 60,
            distanceMeters: 8200,
            calories: 677,
            avgHR: 143,
            type: .run
        )
        let tempo = ActualsPlanCandidate(
            id: "tempo",
            title: "Tempo 40/20s",
            sourceLabel: "STRYD · 12:50 TODAY",
            scheduledStart: noon.addingTimeInterval(-180),
            durationSeconds: 55 * 60,
            distanceMeters: 8000,
            type: .run,
            targetAvgHR: 145
        )
        let zone2 = ActualsPlanCandidate(
            id: "z2",
            title: "Zone 2 base run",
            sourceLabel: "MY WORKOUTS",
            scheduledStart: nil,
            durationSeconds: 60 * 60,
            distanceMeters: 8500,
            type: .run,
            targetAvgHR: 125
        )

        let ranked = ActualsPlanMatcher.rank(activity: activity, candidates: [zone2, tempo])
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked[0].candidate.id, "tempo")
        XCTAssertTrue(ranked[0].isBest)
        XCTAssertFalse(ranked[1].isBest)
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    func testWhyLineSameStartAndDistance() {
        let activity = ActualsUnmappedActivity(
            title: "Run",
            provider: .garmin,
            startDate: noon,
            durationSeconds: 3600,
            distanceMeters: 8000,
            calories: nil,
            avgHR: 140,
            type: .run
        )
        let candidate = ActualsPlanCandidate(
            id: "c1",
            title: "Tempo",
            sourceLabel: "PLAN",
            scheduledStart: noon.addingTimeInterval(60),
            durationSeconds: 3600,
            distanceMeters: 8000,
            type: .run,
            targetAvgHR: 140
        )
        let signals = ActualsPlanMatcher.scoreSignals(activity: activity, candidate: candidate)
        let why = ActualsPlanMatcher.whyLine(from: signals)
        XCTAssertTrue(why.contains("SAME START"), why)
        XCTAssertTrue(why.contains("SAME DISTANCE") || why.contains("SAME DURATION"), why)
    }

    func testWhyLineHRSaysTempoWhenActivityHotterThanPlan() {
        let activity = ActualsUnmappedActivity(
            title: "Run",
            provider: .strava,
            startDate: noon,
            durationSeconds: 3600,
            distanceMeters: 8200,
            calories: nil,
            avgHR: 150,
            type: .run
        )
        let candidate = ActualsPlanCandidate(
            id: "z2",
            title: "Zone 2",
            sourceLabel: "MY WORKOUTS",
            scheduledStart: nil,
            durationSeconds: 3600,
            distanceMeters: 8500,
            type: .run,
            targetAvgHR: 125
        )
        let signals = ActualsPlanMatcher.scoreSignals(activity: activity, candidate: candidate)
        XCTAssertTrue(
            signals.whyFragments.contains("HR SAYS TEMPO"),
            "expected HR shape fragment, got \(signals.whyFragments)"
        )
        // whyLine keeps at most two fragments (duration/distance often win the slots).
        let why = ActualsPlanMatcher.whyLine(from: signals)
        XCTAssertFalse(why.isEmpty)
        XCTAssertTrue(
            why.contains("SAME DURATION")
                || why.contains("SAME DISTANCE")
                || why.contains("DISTANCE FITS")
                || why.contains("HR SAYS TEMPO"),
            why
        )
    }

    func testTypeMismatchScoresLowerThanTypeMatch() {
        let activity = ActualsUnmappedActivity(
            title: "Run",
            provider: .appleHealth,
            startDate: noon,
            durationSeconds: 2400,
            distanceMeters: 5000,
            calories: nil,
            avgHR: nil,
            type: .run
        )
        let run = ActualsPlanCandidate(
            id: "run", title: "Easy run", sourceLabel: "PLAN",
            scheduledStart: noon, durationSeconds: 2400, distanceMeters: 5000,
            type: .run, targetAvgHR: nil
        )
        let strength = ActualsPlanCandidate(
            id: "lift", title: "Lower body", sourceLabel: "PLAN",
            scheduledStart: noon, durationSeconds: 2400, distanceMeters: nil,
            type: .strength, targetAvgHR: nil
        )
        let ranked = ActualsPlanMatcher.rank(activity: activity, candidates: [strength, run])
        XCTAssertEqual(ranked.first?.candidate.id, "run")
    }

    func testKeepAsIsCopyAndAccessibilityIDs() {
        XCTAssertEqual(ActualsCopy.mapAskTitle, "Which workout was this?")
        XCTAssertEqual(ActualsCopy.mapKeepAsIsCTA, "It was just a run — keep as is")
        XCTAssertEqual(ActualsCopy.mapKeepAsIsAccessibilityID, "af_actuals_map_keep_as_is")
        XCTAssertEqual(ActualsCopy.mapCandidateAccessibilityID(1), "af_actuals_map_candidate_1")
        XCTAssertEqual(ActualsCopy.mapCandidateAccessibilityID(2), "af_actuals_map_candidate_2")
    }

    func testKeepAsIsOutcomeStillCountsSemantically() {
        // Document the product rule: keep-as-is is an explicit outcome, not a discard.
        let outcome = ActualsPlanMatchOutcome.keepAsIs
        XCTAssertEqual(outcome, .keepAsIs)
        if case .mapped = outcome {
            XCTFail("keep-as-is must not be mapped")
        }
    }
}
