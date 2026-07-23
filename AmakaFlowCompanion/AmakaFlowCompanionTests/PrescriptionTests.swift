//
//  PrescriptionTests.swift
//  AmakaFlowCompanionTests
//

import XCTest
@testable import AmakaFlowCompanion

final class PrescriptionTests: XCTestCase {

    // MARK: - Fixtures

    private func makeExercise(
        name: String = "Test",
        sets: Int? = nil,
        reps: String? = nil,
        durationSeconds: Int? = nil,
        distance: Double? = nil,
        load: ExerciseLoad? = nil,
        restSeconds: Int? = nil,
        notes: String? = nil
    ) -> Exercise {
        Exercise(
            name: name,
            canonicalName: nil,
            sets: sets,
            reps: reps,
            durationSeconds: durationSeconds,
            load: load,
            restSeconds: restSeconds,
            distance: distance,
            notes: notes,
            supersetGroup: nil
        )
    }

    // MARK: - Ski Erg 500m

    func testSkiErg500mUsesDistancePrimary() {
        let exercise = makeExercise(name: "Ski Erg", distance: 500)

        let prescription = PrescriptionFormatter.effective(from: exercise)

        if case .distance(let meters, let sets) = prescription.primary {
            XCTAssertEqual(meters, 500)
            XCTAssertNil(sets)
        } else {
            XCTFail("Expected distance primary, got \(prescription.primary)")
        }
        XCTAssertEqual(PrescriptionFormatter.line(prescription), "500 m")
    }

    func testSkiErg500mWithSetsFormatsSetsTimesDistance() {
        let exercise = makeExercise(name: "Ski Erg", sets: 3, distance: 500)

        let prescription = PrescriptionFormatter.effective(from: exercise)

        if case .distance(let meters, let sets) = prescription.primary {
            XCTAssertEqual(meters, 500)
            XCTAssertEqual(sets, 3)
        } else {
            XCTFail("Expected distance primary, got \(prescription.primary)")
        }
        XCTAssertEqual(PrescriptionFormatter.line(prescription), "3 × 500 m")
    }

    // MARK: - Rep range

    func testRepRangeParsesFromRepsString() {
        let exercise = makeExercise(name: "Squat", sets: 3, reps: "8-10")

        let prescription = PrescriptionFormatter.effective(from: exercise)

        if case .repsRange(let range, let sets) = prescription.primary {
            XCTAssertEqual(range.low, 8)
            XCTAssertEqual(range.high, 10)
            XCTAssertEqual(sets, 3)
        } else {
            XCTFail("Expected repsRange primary, got \(prescription.primary)")
        }
        XCTAssertEqual(PrescriptionFormatter.line(prescription), "3 × 8-10")
    }

    func testRepRangeWithoutSetsShowsRangeOnly() {
        let exercise = makeExercise(reps: "8-10")

        let line = PrescriptionFormatter.line(PrescriptionFormatter.effective(from: exercise))
        XCTAssertEqual(line, "8-10")
    }

    // MARK: - Plain reps vs range priority

    func testPlainRepsWinsOverStructuredRange() {
        let primary = PrescriptionFormatter.resolvePrimaryMetric(
            durationSeconds: nil,
            distanceMeters: nil,
            calories: nil,
            plainReps: 10,
            repsRange: RepsRange(low: 8, high: 10),
            sets: 3
        )

        if case .reps(let reps, let sets) = primary {
            XCTAssertEqual(reps, 10)
            XCTAssertEqual(sets, 3)
        } else {
            XCTFail("Expected reps primary when both plain reps and range exist, got \(primary)")
        }
    }

    func testIntegerRepsStringWinsOverRangeParse() {
        let exercise = makeExercise(sets: 3, reps: "10")

        let prescription = PrescriptionFormatter.effective(from: exercise)

        if case .reps(let reps, let sets) = prescription.primary {
            XCTAssertEqual(reps, 10)
            XCTAssertEqual(sets, 3)
        } else {
            XCTFail("Expected reps primary, got \(prescription.primary)")
        }
        XCTAssertEqual(PrescriptionFormatter.line(prescription), "3 × 10")
    }

    // MARK: - reps: 0 treated as nil

    func testZeroRepsStringFallsThroughToNone() {
        let exercise = makeExercise(sets: 3, reps: "0")

        let prescription = PrescriptionFormatter.effective(from: exercise)

        if case .none(let sets) = prescription.primary {
            XCTAssertEqual(sets, 3)
        } else {
            XCTFail("Expected none primary for reps 0, got \(prescription.primary)")
        }
    }

    // MARK: - Modality priority

    func testDurationWinsOverReps() {
        let exercise = makeExercise(sets: 3, reps: "10", durationSeconds: 45)

        if case .duration(let seconds, let sets) = PrescriptionFormatter.effective(from: exercise).primary {
            XCTAssertEqual(seconds, 45)
            XCTAssertEqual(sets, 3)
        } else {
            XCTFail("Expected duration primary")
        }
    }

    func testDistanceWinsOverReps() {
        let exercise = makeExercise(sets: 3, reps: "10", distance: 500)

        if case .distance = PrescriptionFormatter.effective(from: exercise).primary {
            // expected
        } else {
            XCTFail("Expected distance primary")
        }
    }

    // MARK: - RepsRange parsing

    func testRepsRangeParseAcceptsToSeparator() {
        let range = RepsRange.parse("6 to 8")
        XCTAssertEqual(range, RepsRange(low: 6, high: 8, qualifier: nil))
    }

    func testRepsRangeParseCapturesQualifier() {
        let range = RepsRange.parse("6-8 each leg")
        XCTAssertEqual(range?.low, 6)
        XCTAssertEqual(range?.high, 8)
        XCTAssertEqual(range?.qualifier, "each leg")
    }

    func testRepsRangeEqualBoundsCollapseToNil() {
        XCTAssertNil(RepsRange.parse("10-10"))
    }

    // MARK: - Secondary parts

    func testSecondaryIncludesLoadRestAndNotes() {
        let exercise = makeExercise(
            sets: 3,
            reps: "8",
            load: ExerciseLoad(value: 40, unit: "kg"),
            restSeconds: 60,
            notes: "Controlled tempo"
        )

        let prescription = PrescriptionFormatter.effective(from: exercise)
        let line = PrescriptionFormatter.line(prescription)

        XCTAssertTrue(line.contains("3 × 8"))
        XCTAssertTrue(line.contains("40 kg"))
        XCTAssertTrue(line.contains("60S REST"))
        XCTAssertTrue(line.contains("Controlled tempo"))
    }

    func testQualifierAppendedAsSecondaryForRange() {
        let exercise = makeExercise(reps: "6-8 each leg")

        let prescription = PrescriptionFormatter.effective(from: exercise)
        XCTAssertTrue(prescription.secondary.contains("each leg"))
        XCTAssertTrue(PrescriptionFormatter.line(prescription).contains("each leg"))
    }
}
