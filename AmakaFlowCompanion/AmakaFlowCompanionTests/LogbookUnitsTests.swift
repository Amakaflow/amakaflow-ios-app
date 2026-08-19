//
//  LogbookUnitsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2462 slice 1 — the unit preferences already exist in Profile; the logbook
//  has to obey them. Three defects covered here:
//    1. `WeightUnit.stored` fell back to .kg while the Profile picker declares .lbs
//    2. `user.distanceUnit` was read by nothing at all
//    3. logbook distance was hardcoded to kilometres
//  Plus the rule that an erg reports metres no matter what the athlete picked.
//

import XCTest
@testable import AmakaFlowCompanion

final class LogbookUnitsTests: XCTestCase {

    private let weightKey = DefaultsKey.userWeightUnit.rawValue
    private let distanceKey = DefaultsKey.userDistanceUnit.rawValue
    private var savedWeight: String?
    private var savedDistance: String?

    override func setUp() {
        super.setUp()
        savedWeight = UserDefaults.standard.string(forKey: weightKey)
        savedDistance = UserDefaults.standard.string(forKey: distanceKey)
        UserDefaults.standard.removeObject(forKey: weightKey)
        UserDefaults.standard.removeObject(forKey: distanceKey)
    }

    override func tearDown() {
        if let savedWeight {
            UserDefaults.standard.set(savedWeight, forKey: weightKey)
        } else {
            UserDefaults.standard.removeObject(forKey: weightKey)
        }
        if let savedDistance {
            UserDefaults.standard.set(savedDistance, forKey: distanceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: distanceKey)
        }
        super.tearDown()
    }

    // MARK: - Defect 1: the screen must not lie about the default

    /// `EditProfileView` declares `@AppStorage(...) weightUnit: WeightUnit = .lbs`, and
    /// `@AppStorage` writes nothing until the picker is touched. A different fallback
    /// here means Profile shows "lbs" while the logbook renders kilograms.
    func testStoredWeightUnitMatchesTheProfilePickerDefault() {
        XCTAssertEqual(
            WeightUnit.stored, .lbs,
            "unset must resolve to the same unit the Profile picker shows"
        )
    }

    func testStoredDistanceUnitMatchesTheProfilePickerDefault() {
        XCTAssertEqual(
            DistanceUnit.stored, .mi,
            "unset must resolve to the same unit the Profile picker shows"
        )
    }

    func testStoredUnitsHonourAnExplicitChoice() {
        UserDefaults.standard.set(WeightUnit.kg.rawValue, forKey: weightKey)
        UserDefaults.standard.set(DistanceUnit.km.rawValue, forKey: distanceKey)
        XCTAssertEqual(WeightUnit.stored, .kg)
        XCTAssertEqual(DistanceUnit.stored, .km)
    }

    /// The two preferences are separate keys on purpose: training in kilograms while
    /// running in miles is a legitimate combination and must stay expressible.
    func testWeightAndDistancePreferencesAreIndependent() {
        UserDefaults.standard.set(WeightUnit.kg.rawValue, forKey: weightKey)
        UserDefaults.standard.set(DistanceUnit.mi.rawValue, forKey: distanceKey)
        XCTAssertEqual(WeightUnit.stored, .kg, "kilograms")
        XCTAssertEqual(DistanceUnit.stored, .mi, "…with miles")
    }

    // MARK: - Erg scale: machine-native, not a preference

    func testErgsReportMetresRegardlessOfPreference() {
        for name in ["Ski Erg", "SkiErg", "Rower", "Bike Erg", "Concept2 Rower"] {
            let scale = LogbookDistanceScale.forExercise(named: name)
            XCTAssertEqual(scale, .machineMetres, "\(name) is machine-native metres")
            XCTAssertEqual(
                LogbookMetricFormat.distance(meters: 500, scale: scale, unit: .mi), "500 M",
                "\(name) must stay metres even for an athlete set to miles"
            )
            XCTAssertEqual(
                LogbookMetricFormat.distance(meters: 500, scale: scale, unit: .km), "500 M"
            )
        }
    }

    /// The trap: "Dumbbell Gorilla Row" contains "row" but is not a rower. Substring
    /// matching would misclassify it and pin a barbell movement to metres.
    func testRowIsNotARower() {
        XCTAssertEqual(
            LogbookDistanceScale.forExercise(named: "Dumbbell Gorilla Row"), .road,
            "a row is not a rower"
        )
        XCTAssertEqual(
            LogbookDistanceScale.forExercise(named: "Barbell Bent-Over Row"), .road
        )
        // "energy" contains the letters "erg".
        XCTAssertEqual(
            LogbookDistanceScale.forExercise(named: "Energy System Intervals"), .road
        )
    }

    // MARK: - Defect 2 + 3: road distance follows the preference

    func testRoadDistanceFollowsThePreference() {
        XCTAssertEqual(
            LogbookMetricFormat.distance(meters: 8_046.72, scale: .road, unit: .mi), "5 MI"
        )
        XCTAssertEqual(
            LogbookMetricFormat.distance(meters: 8_000, scale: .road, unit: .km), "8 KM"
        )
    }

    func testRoadDistanceKeepsOneDecimalWhenItIsNotWhole() {
        XCTAssertEqual(
            LogbookMetricFormat.distance(meters: 5_000, scale: .road, unit: .km), "5 KM"
        )
        XCTAssertEqual(
            LogbookMetricFormat.distance(meters: 5_500, scale: .road, unit: .km), "5.5 KM"
        )
    }

    /// A ghost with no exercise context must still render in the athlete's units.
    func testGhostDistanceRendersInTheChosenScale() {
        let ghost = LogbookGhost(distanceMeters: 500, source: .prescription)
        XCTAssertEqual(
            ghost.metricDisplayLine(scale: .machineMetres, distanceUnit: .mi), "500 M"
        )
        let run = LogbookGhost(distanceMeters: 8_000, source: .prescription)
        XCTAssertEqual(
            run.metricDisplayLine(scale: .road, distanceUnit: .km), "8 KM"
        )
    }

    func testPlannedLineForAnErgReadsMetres() {
        var entry = LogbookExerciseEntry(
            id: "e1",
            name: "Ski Erg",
            planned: ExerciseActualPlanned(sets: 3, reps: 1, weightKg: nil),
            sets: [SetActual(index: 1)],
            ghosts: [],
            loggingKind: .metric
        )
        entry.plannedDistanceMeters = 500
        UserDefaults.standard.set(DistanceUnit.mi.rawValue, forKey: distanceKey)
        XCTAssertEqual(
            entry.plannedLine, "PLANNED 500 M",
            "a prescribed erg distance is metres, not 0.31 miles"
        )
    }
}
