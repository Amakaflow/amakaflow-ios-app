//
//  BuilderV3ExerciseIconTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2450 — per-row icon chip in the exercise picker.
//

import SwiftUI
import XCTest
@testable import AmakaFlowCompanion

final class BuilderV3ExerciseIconTests: XCTestCase {

    func testCardioEquipmentGetsItsOwnGlyphRatherThanTheStrengthDefault() {
        XCTAssertEqual(
            BuilderV3ExerciseIcon.systemImage(equipmentKey: "treadmill"),
            "figure.run",
            "a treadmill row must not show a dumbbell"
        )
        XCTAssertEqual(
            BuilderV3ExerciseIcon.systemImage(equipmentKey: "assault_bike"),
            "bicycle",
            "bikes get the bike glyph"
        )
        XCTAssertEqual(
            BuilderV3ExerciseIcon.systemImage(equipmentKey: "stair_climber"),
            "figure.stairs",
            "stair climber gets the stairs glyph"
        )
    }

    func testLoadedMovementsFallBackToTheDumbbellGlyph() {
        for key in ["barbell", "dumbbells", "kettlebells", "cable", "machine", "ab_wheel"] {
            XCTAssertEqual(
                BuilderV3ExerciseIcon.systemImage(equipmentKey: key),
                "dumbbell.fill",
                "\(key) should read as a loaded movement"
            )
        }
    }

    /// `equipmentKey == nil` is the catalogue's bodyweight convention.
    func testBodyweightIsDistinctFromLoadedMovements() {
        let bodyweight = BuilderV3ExerciseIcon.systemImage(equipmentKey: nil)
        XCTAssertEqual(bodyweight, BuilderV3ExerciseIcon.systemImage(equipmentKey: "bodyweight"))
        XCTAssertEqual(bodyweight, BuilderV3ExerciseIcon.systemImage(equipmentKey: ""))
        XCTAssertNotEqual(
            bodyweight,
            BuilderV3ExerciseIcon.systemImage(equipmentKey: "barbell"),
            "bodyweight and barbell must be distinguishable at a glance"
        )
    }

    func testAnUnknownCatalogueKeyStillGetsAGlyph() {
        XCTAssertFalse(
            BuilderV3ExerciseIcon.systemImage(equipmentKey: "some_future_machine").isEmpty,
            "an unenumerated key must never produce an empty symbol name"
        )
    }

    /// A misspelled SF Symbol renders as blank space, which no unit test would
    /// otherwise catch — so resolve every name this type can return.
    func testEveryGlyphResolvesToARealSFSymbol() {
        let keys: [String?] = [
            nil, "", "bodyweight", "barbell", "dumbbells", "kettlebells", "cable",
            "machine", "treadmill", "assault_bike", "stationary_bike",
            "stair_climber", "ski_erg", "rowing_machine", "unknown_key"
        ]
        for key in keys {
            let name = BuilderV3ExerciseIcon.systemImage(equipmentKey: key)
            XCTAssertNotNil(
                UIImage(systemName: name),
                "\(name) is not a real SF Symbol — it would render as blank space"
            )
        }
    }
}
