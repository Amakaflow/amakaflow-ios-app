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
        XCTAssertEqual(
            LogbookCopy.columnWeight(for: .lbs, added: true), "+LB",
            "the column header must say the load is added"
        )
    }

    func testLoadOnABarbellMovementIsAbsoluteNotAdded() {
        XCTAssertFalse(
            entry("Back Squat", weightKg: 100).showsAddedLoad,
            "a squat is absolute load — a + prefix would misstate it"
        )
        XCTAssertEqual(
            LogbookCopy.columnWeight(for: .lbs, added: false), "LB",
            "absolute load carries no +"
        )
    }

    // MARK: - Metric stations follow the plan

    func testSkiErgPrescribedByTimeTracksTimeOnly() {
        let ski = entry("Ski Erg", kind: .metric, duration: 120)
        XCTAssertEqual(ski.trackedFields, [.time], "no reps, no load, no distance")
    }

    func testRowerPrescribedByDistanceTracksTimeAndDistance() {
        let rower = entry("Rower", kind: .metric, duration: 112, distance: 500)
        XCTAssertEqual(
            rower.trackedFields, [.time, .distance],
            "a 500 m row is prescribed by distance and timed"
        )
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
        let legacy = try XCTUnwrap("""
        {"id":"chin_up","name":"Chin-Up",
         "planned":{"sets":3,"reps":10},
         "sets":[],"ghosts":[],"loggingKind":"strength"}
        """.data(using: .utf8))
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

    // MARK: - CodeRabbit: a weighted pull-up is BOTH bodyweight and loaded

    /// The flaw: one predicate was answering two different questions, so
    /// "Weighted Pull-Up" fell out of the bodyweight class entirely and its
    /// load rendered as absolute — 25, not +25.
    func testWeightedBodyweightMovementStillReadsAsAddedLoad() {
        let weighted = entry("Weighted Pull-Up")
        XCTAssertTrue(weighted.tracks(.weight), "the name says it is loaded")
        XCTAssertTrue(
            weighted.showsAddedLoad,
            "a weighted pull-up is still a bodyweight movement — the load is ADDED"
        )
        XCTAssertTrue(entry("Machine Dip").showsAddedLoad, "assisted/loaded dip is still added")
    }

    func testMovementClassAnswersTheTwoQuestionsSeparately() {
        XCTAssertTrue(LogbookMovementClass.isBodyweight(named: "Weighted Pull-Up"))
        XCTAssertTrue(LogbookMovementClass.nameImpliesLoad("Weighted Pull-Up"))
        XCTAssertTrue(LogbookMovementClass.isBodyweight(named: "Chin-Up"))
        XCTAssertFalse(LogbookMovementClass.nameImpliesLoad("Chin-Up"))
        XCTAssertFalse(LogbookMovementClass.isBodyweight(named: "Back Squat"))
    }

    /// An empty choice would leave a row with nowhere to log, so it is never
    /// stored — the flag means "never chosen" and nothing else.
    func testTurningEverythingOffFallsBackRatherThanLeavingAnEmptyRow() {
        var row = entry("Chin-Up")
        row.trackedFieldsOverride = []
        XCTAssertNil(row.trackedFieldsOverride, "an empty set is not stored")
        XCTAssertFalse(row.trackedFields.isEmpty, "a row always has somewhere to log")
    }

    /// The ghost, the grid and the wheel sheet must agree.
    func testGhostStatesAddedLoadWithThePrefix() {
        // Derive the kilograms from 25 lb rather than hardcoding an approximation.
        let twentyFivePounds = WeightUnitMath.kilograms(fromDisplay: 25, unit: .lbs)
        let ghost = LogbookGhost(weightKg: twentyFivePounds, reps: 8, source: .lastActual)
        XCTAssertEqual(
            ghost.displayLine(unit: .lbs, addedLoad: true), "+25 × 8",
            "an added-load ghost carries the +"
        )
        XCTAssertEqual(
            ghost.displayLine(unit: .lbs, addedLoad: false), "25 × 8",
            "an absolute-load ghost must not"
        )
    }

    /// Verified history is where a mis-stated load does lasting damage.
    func testVerifiedHistoryKeepsAddedLoadPrefix() {
        let actual = ExerciseActual(
            id: "chin_up",
            name: "Chin-Up",
            planned: ExerciseActualPlanned(sets: 1, reps: 8, weightKg: 11.3),
            sets: [SetActual(index: 1, weightKg: 11.3, reps: 8, checkedAt: Date())]
        )
        XCTAssertTrue(
            actual.actualDisplayLine.contains("+"),
            "a belted chin-up must not read as an absolute lift — got \(actual.actualDisplayLine)"
        )
    }

    /// CodeRabbit: the setter clamped empty to nil but the initializer did not,
    /// so the same field could mean "chose nothing" one way in and "never
    /// chosen" the other — and would persist as `"trackedFields": []`.
    func testAnEmptyChoicePassedToTheInitializerIsNotStored() throws {
        let row = entry("Chin-Up", tracked: [])
        XCTAssertNil(row.trackedFieldsOverride, "an empty set is never stored, whichever way in")
        XCTAssertEqual(row.trackedFields, [.reps], "it falls through to the plan's default")

        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(row), encoding: .utf8))
        XCTAssertFalse(
            json.contains("\"trackedFields\":[]"),
            "an empty array must not reach disk — got \(json)"
        )
    }

    /// CodeRabbit, third time on this field: init and the setter clamped an
    /// empty selection, the DECODER did not. A draft holding `"trackedFields":[]`
    /// stayed non-nil and re-encoded as an empty override. All three ways in now
    /// go through one normalizer.
    func testDecodingNormalizesAnEmptyOrUnorderedSelection() throws {
        let empty = try XCTUnwrap("""
        {"id":"chin_up","name":"Chin-Up","planned":{"sets":3,"reps":10},
         "sets":[],"ghosts":[],"loggingKind":"strength","trackedFields":[]}
        """.data(using: .utf8))
        let decodedEmpty = try JSONDecoder().decode(LogbookExerciseEntry.self, from: empty)
        XCTAssertNil(
            decodedEmpty.trackedFieldsOverride,
            "an empty stored selection means never-chosen after decoding too"
        )

        let unordered = try XCTUnwrap("""
        {"id":"chin_up","name":"Chin-Up","planned":{"sets":3,"reps":10},
         "sets":[],"ghosts":[],"loggingKind":"strength",
         "trackedFields":["reps","weight"]}
        """.data(using: .utf8))
        let decodedUnordered = try JSONDecoder().decode(LogbookExerciseEntry.self, from: unordered)
        XCTAssertEqual(
            decodedUnordered.trackedFieldsOverride, [.weight, .reps],
            "a stored selection is canonicalised on the way in, not just on the way out"
        )

        let json = try XCTUnwrap(
            String(data: try JSONEncoder().encode(decodedEmpty), encoding: .utf8)
        )
        XCTAssertFalse(
            json.contains("\"trackedFields\":[]"),
            "and an empty override must not survive a round trip — got \(json)"
        )
    }
}
