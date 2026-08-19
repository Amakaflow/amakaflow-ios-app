//
//  LogbookTrackedFieldsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2462 slice 2 — the plan proposes the fields, the athlete decides.
//  A field that is off must be ABSENT, and a load on a bodyweight movement
//  must read as ADDED load or Progress will treat +25 as an absolute 200.
//

import XCTest
@testable import AmakaFlowCompanion

final class LogbookTrackedFieldsTests: XCTestCase {

    private func entry(
        _ name: String,
        kind: LogbookLoggingKind = .strength,
        weightKg: Double? = nil,
        duration: Int? = nil,
        distance: Int? = nil,
        calories: Int? = nil,
        tracked: [LogbookTrackedField]? = nil
    ) -> LogbookExerciseEntry {
        LogbookExerciseEntry(
            id: name.lowercased(),
            name: name,
            planned: ExerciseActualPlanned(sets: 3, reps: 10, weightKg: weightKg),
            sets: [SetActual(index: 1)],
            ghosts: [],
            loggingKind: kind,
            plannedDurationSeconds: duration,
            plannedCalories: calories,
            plannedDistanceMeters: distance,
            trackedFields: tracked
        )
    }

    // MARK: - Bodyweight: the load column is absent, not zeroed

    func testBodyweightMovementTracksRepsOnly() {
        for name in ["Chin-Up", "Pull Ups", "Dips", "Push-Up", "Burpees", "Toes to Bar"] {
            let row = entry(name)
            XCTAssertEqual(
                row.trackedFields, [.reps],
                "\(name) is unloaded — the weight column must not exist at all"
            )
            XCTAssertFalse(row.tracks(.weight), "\(name) must not ask for a load")
        }
    }

    func testLoadedMovementKeepsTheWeightColumn() {
        for name in ["Dumbbell Gorilla Row", "Back Squat", "Bench Press", "Medicine Ball Slam"] {
            let row = entry(name)
            XCTAssertTrue(
                row.tracks(.weight),
                "\(name) takes external load — the column must stay"
            )
            XCTAssertEqual(row.trackedFields, [.weight, .reps], "canonical column order")
        }
    }

    /// The classifier trap: a false positive silently removes the load column
    /// from a movement the athlete actually loads.
    func testQualifiersOverrideTheBodyweightGuess() {
        XCTAssertTrue(
            entry("Weighted Pull-Up").tracks(.weight),
            "\"weighted\" says it is loaded — do not hide the column"
        )
        XCTAssertTrue(
            entry("Dumbbell Push Up").tracks(.weight),
            "an implement in the name means load"
        )
        XCTAssertTrue(
            entry("Machine Dip").tracks(.weight),
            "a machine dip carries a stack"
        )
    }

    /// A prescribed load beats the name — if the plan says 25 kg, show the column.
    func testPrescribedLoadKeepsTheColumnOnABodyweightMovement() {
        XCTAssertTrue(
            entry("Chin-Up", weightKg: 11.3).tracks(.weight),
            "the plan prescribed a load, so it must be enterable"
        )
    }

    // MARK: - Added load semantics

    func testLoadOnABodyweightMovementIsAdded() {
        let belted = entry("Chin-Up", weightKg: 11.3)
        XCTAssertTrue(
            belted.showsAddedLoad,
            "a belted chin-up logs +25, never 200 — Progress depends on this"
        )
        XCTAssertEqual(LogbookCopy.columnWeight(for: .lbs, added: true), "+LB")
    }

    func testLoadOnABarbellMovementIsAbsoluteNotAdded() {
        XCTAssertFalse(
            entry("Back Squat", weightKg: 100).showsAddedLoad,
            "a squat is absolute load — a + prefix would misstate it"
        )
        XCTAssertEqual(LogbookCopy.columnWeight(for: .lbs, added: false), "LB")
    }

    // MARK: - Metric stations follow the plan

    func testSkiErgPrescribedByTimeTracksTimeOnly() {
        let ski = entry("Ski Erg", kind: .metric, duration: 120)
        XCTAssertEqual(ski.trackedFields, [.time], "no reps, no load, no distance")
    }

    func testRowerPrescribedByDistanceTracksTimeAndDistance() {
        let rower = entry("Rower", kind: .metric, duration: 112, distance: 500)
        XCTAssertEqual(rower.trackedFields, [.time, .distance])
    }

    func testAssaultBikePrescribedByCaloriesTracksCalories() {
        let bike = entry("Assault Bike", kind: .metric, calories: 15)
        XCTAssertEqual(bike.trackedFields, [.calories], "calories is what the machine reports")
    }

    func testMetricStationWithNothingPrescribedStillHasSomewhereToLog() {
        let station = entry("Sled Push", kind: .metric)
        XCTAssertEqual(station.trackedFields, [.time], "never leave a station with zero fields")
    }

    // MARK: - The athlete's choice wins

    func testAnExplicitChoiceOverridesThePlan() {
        let ski = entry("Ski Erg", kind: .metric, duration: 120, distance: 500, tracked: [.time])
        XCTAssertEqual(
            ski.trackedFields, [.time],
            "distance was turned off — it must be gone even though the plan proposed it"
        )
    }

    func testChoiceIsStoredInCanonicalOrder() {
        let row = entry("Chin-Up", tracked: [.reps, .weight])
        XCTAssertEqual(
            row.trackedFields, [.weight, .reps],
            "columns must not reshuffle based on the order fields were toggled"
        )
    }

    // MARK: - Persistence

    /// Drafts written before this existed carry no key. They must decode and
    /// fall through to the derived defaults rather than throwing.
    func testDraftsWrittenBeforeTrackedFieldsStillDecode() throws {
        let legacy = """
        {"id":"chin_up","name":"Chin-Up",
         "planned":{"sets":3,"reps":10},
         "sets":[],"ghosts":[],"loggingKind":"strength"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LogbookExerciseEntry.self, from: legacy)
        XCTAssertEqual(
            decoded.trackedFields, [.reps],
            "a legacy draft falls through to the derived default"
        )
    }

    func testAnExplicitChoiceSurvivesARoundTrip() throws {
        let original = entry("Ski Erg", kind: .metric, duration: 120, tracked: [.time, .calories])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LogbookExerciseEntry.self, from: data)
        XCTAssertEqual(
            decoded.trackedFields, [.time, .calories],
            "the athlete's choice must stick across a save and reopen"
        )
    }
}
