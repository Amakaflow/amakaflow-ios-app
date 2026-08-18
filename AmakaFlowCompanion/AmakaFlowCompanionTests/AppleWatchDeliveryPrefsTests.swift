//
//  AppleWatchDeliveryPrefsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2360 — Apple delivery prefs persistence + mapper delivery_prefs payload.
//

import XCTest
@testable import AmakaFlowCompanion

final class AppleWatchDeliveryPrefsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppleWatchDeliveryPrefsStore.resetForTests()
    }

    override func tearDown() {
        AppleWatchDeliveryPrefsStore.resetForTests()
        super.tearDown()
    }

    func testDogfoodDefaultsMatchSpecStrength() {
        let prefs = AppleWatchDeliveryPrefs.dogfood
        XCTAssertEqual(prefs.exerciseEnd, .tap)
        XCTAssertEqual(prefs.restMode, .timed)
        XCTAssertFalse(prefs.alertsEnabled)
    }

    func testUnconfiguredMapperPrefsAreNil() {
        XCTAssertFalse(AppleWatchDeliveryPrefsStore.hasConfigured)
        XCTAssertNil(AppleWatchDeliveryPrefsStore.deliveryPrefsForMapper)
        XCTAssertTrue(
            AppleWatchDeliveryPrefsStore.previewSummaryLine
                .localizedCaseInsensitiveContains("defaults")
        )
    }

    func testDeliveryPrefsDictionaryUsesSnakeCaseAppleValues() {
        let prefs = AppleWatchDeliveryPrefs(
            exerciseEnd: .timedHoldsOnly,
            restMode: .omit,
            alertsEnabled: false
        )
        let dict = prefs.deliveryPrefsDictionary
        XCTAssertEqual(dict["exercise_end"] as? String, "timed_holds_only")
        XCTAssertEqual(dict["rest_mode"] as? String, "omit")
        XCTAssertEqual(dict["alerts_enabled"] as? Bool, false)
        // Must never send Garmin lap aliases
        XCTAssertNotEqual(dict["exercise_end"] as? String, "lap")
        XCTAssertNotEqual(dict["rest_mode"] as? String, "lap")
    }

    func testPersistAndLiveSelectionSurvivesReload() throws {
        AppleWatchDeliveryPrefsStore.applyLiveSelection(restMode: .tap)
        XCTAssertTrue(AppleWatchDeliveryPrefsStore.hasConfigured)

        let data = try XCTUnwrap(
            UserDefaults.standard.data(forKey: DefaultsKey.appleWatchDeliveryPrefs.rawValue)
        )
        let decoded = try JSONDecoder().decode(AppleWatchDeliveryPrefs.self, from: data)
        XCTAssertEqual(decoded.restMode, .tap)
        XCTAssertEqual(AppleWatchDeliveryPrefsStore.deliveryPrefsForMapper?["rest_mode"] as? String, "tap")
        XCTAssertTrue(
            AppleWatchDeliveryPrefsStore.previewSummaryLine.localizedCaseInsensitiveContains("tap")
        )
    }

    func testStepSummaryIncludesWarmupAndRest() throws {
        let json = """
        {
          "title": "Test",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            { "kind": "warmup", "seconds": 300 },
            {
              "kind": "repeat",
              "reps": 3,
              "intervals": [
                { "kind": "work", "name": "Squat", "reps": 8 },
                { "kind": "rest", "seconds": 60 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        let lines = WorkoutKitPlanStepSummary.lines(from: json)
        XCTAssertFalse(lines.isEmpty, "DTO should decode fixture intervals")
        XCTAssertTrue(lines.contains { $0.contains("Warm-up") })
        XCTAssertTrue(lines.contains { $0.contains("Squat") })
        XCTAssertTrue(lines.contains { $0.localizedCaseInsensitiveContains("rest") })
    }

    func testStepSummaryRespectsHardLimit() throws {
        let intervals = (0..<20).map { i in
            "{\"kind\":\"work\",\"name\":\"Move \(i)\",\"reps\":5}"
        }.joined(separator: ",")
        let json = """
        {"title":"Long","sportType":"traditionalStrengthTraining","intervals":[\(intervals)]}
        """.data(using: .utf8)!
        let limit = 5
        let lines = WorkoutKitPlanStepSummary.lines(from: json, limit: limit)
        XCTAssertEqual(lines.count, limit)
        XCTAssertTrue(lines.last?.hasPrefix("… +") == true)
    }

    func testStepSummaryTruncatesAfterRepeatWhenLaterIntervalExists() throws {
        let json = """
        {
          "title": "Test",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            {
              "kind": "repeat",
              "reps": 3,
              "intervals": [
                { "kind": "work", "name": "Squat", "reps": 8 },
                { "kind": "rest", "seconds": 60 }
              ]
            },
            { "kind": "cooldown", "seconds": 120 }
          ]
        }
        """.data(using: .utf8)!
        let lines = WorkoutKitPlanStepSummary.lines(from: json, limit: 2)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("Repeat"))
        XCTAssertTrue(lines[1].hasPrefix("… +"), "omitted nested rest + cooldown need a marker")
    }

    func testSectionsBandRestIntoChipsNotMonospaceDump() throws {
        let json = """
        {
          "title": "Test",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            { "kind": "warmup", "seconds": 300 },
            {
              "kind": "repeat",
              "reps": 3,
              "intervals": [
                { "kind": "work", "name": "Squat", "reps": 8 },
                { "kind": "rest", "seconds": 60 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)

        XCTAssertFalse(sections.isEmpty, "expect at least one section band")
        XCTAssertEqual(sections.map(\.band), ["Mobility prep", "Squat"])
        XCTAssertFalse(
            sections.contains { $0.band == "WARM-UP" || $0.band == "WORK" || $0.band == "COOL-DOWN" },
            "bands must be exercise-named, not WorkoutKit kind labels"
        )
        XCTAssertEqual(sections[1].tag, "3 SETS")
        XCTAssertEqual(sections[1].steps.first?.title, "Working sets ×3")
        XCTAssertEqual(sections[1].steps.first?.restChip, "REST 60S")

        let allChips = sections.flatMap { $0.steps.compactMap(\.restChip) }
        XCTAssertFalse(allChips.isEmpty, "rest interval should produce a chip, not a plain line")
        XCTAssertTrue(
            allChips.contains { $0 == "REST 60S" || $0 == "REST · YOU END IT" },
            "rest chip must use the exact banded copy, got: \(allChips)"
        )

        // Rest must never show up as a monospace dump line inside a step title/detail.
        let allTitlesAndDetails = sections.flatMap { section in
            section.steps.flatMap { [$0.title, $0.detail ?? ""] }
        }
        XCTAssertFalse(
            allTitlesAndDetails.contains { $0.localizedCaseInsensitiveContains("rest ·") },
            "rest should be demoted to a chip, not left as a 'Rest · 60s' dump line"
        )

        let allPublicText = sections.flatMap { section -> [String] in
            [section.band, section.tag ?? ""] + section.steps.flatMap { [$0.title, $0.detail ?? "", $0.restChip ?? ""] }
        }
        XCTAssertFalse(
            allPublicText.contains { $0.localizedCaseInsensitiveContains("from mapper") },
            "Apple Watch preview must demote mapper jargon"
        )
    }

    func testSectionsUseExerciseNamedBandsLikeRedesign() throws {
        let json = """
        {
          "title": "Test Apple workout",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            { "kind": "work", "name": "Jump Rope", "seconds": 120 },
            { "kind": "work", "name": "WU · Barbell back squat", "reps": 8 },
            { "kind": "rest" },
            { "kind": "work", "name": "WU · Barbell back squat", "reps": 5 },
            { "kind": "rest" },
            {
              "kind": "repeat",
              "reps": 3,
              "intervals": [
                { "kind": "work", "name": "Barbell back squat", "reps": 10 },
                { "kind": "rest" }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        XCTAssertEqual(sections.map(\.band), ["Mobility prep", "Barbell back squat"])
        XCTAssertEqual(sections[0].steps.map(\.title), ["Jump Rope"])
        XCTAssertEqual(sections[0].tag, "~2 MIN", "120s Jump Rope must aggregate to a minute tag")
        XCTAssertEqual(sections[1].tag, "5 SETS")
        XCTAssertEqual(
            sections[1].steps.map(\.title),
            ["Warm-up set", "Warm-up set", "Working sets ×3"]
        )
        XCTAssertTrue(sections[1].steps.allSatisfy { $0.restChip == "REST · YOU END IT" })
        XCTAssertEqual(sections.flatMap(\.steps).map(\.number), [1, 2, 3, 4])
    }

    func testSectionsEmitCoolDownBandAndDropTrailingRest() throws {
        let json = """
        {
          "title": "Cooldown",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            { "kind": "work", "name": "Squat", "reps": 5 },
            { "kind": "rest", "seconds": 60 },
            { "kind": "cooldown", "seconds": 120 },
            { "kind": "rest" }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        XCTAssertEqual(sections.map(\.band), ["Squat", "Cool-down"])
        XCTAssertEqual(sections[0].steps.first?.restChip, "REST 60S")
        XCTAssertEqual(sections[1].steps.map(\.title), ["Cool-down"])
        XCTAssertEqual(sections[1].steps.first?.detail, "2 MIN")
        // Trailing open rest after cool-down has nothing to pin to — dropped.
        XCTAssertNil(sections[1].steps.first?.restChip)
        XCTAssertFalse(sections.flatMap(\.steps).contains { $0.restChip == "REST · YOU END IT" })
    }

    func testEmomRepeatBandsPerStationWithoutWorkingSetLabel() throws {
        let json = """
        {
          "title": "EMOM",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            {
              "kind": "repeat",
              "reps": 4,
              "intervals": [
                { "kind": "work", "name": "EMOM · Assault Bike", "seconds": 60 },
                { "kind": "work", "name": "EMOM · Rower", "seconds": 60 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.band), ["EMOM · Assault Bike", "EMOM · Rower"])
        XCTAssertFalse(sections.flatMap(\.steps).contains { $0.title.hasPrefix("Working set") })
        XCTAssertEqual(sections[0].steps.first?.title, "Work intervals ×4")
    }

    /// AMA-2390 — distance stations inside a multi-step circuit keep meters in detail
    /// (not the open-goal fallback).
    func testDistanceCircuitStationPreservesMetersDetail() throws {
        let json = """
        {
          "title": "Row ski circuit",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            {
              "kind": "repeat",
              "reps": 4,
              "intervals": [
                { "kind": "distance", "name": "Rowing Machine", "meters": 500 },
                { "kind": "work", "name": "Ski Erg", "seconds": 60 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].band, "Circuit")
        XCTAssertEqual(sections[0].tag, "4 ROUNDS")
        XCTAssertEqual(sections[0].steps.map(\.title), ["Rowing Machine", "Ski Erg"])
        XCTAssertEqual(sections[0].steps[0].detail, "500M")
        XCTAssertNotEqual(sections[0].steps[0].detail, "OPEN")
        XCTAssertEqual(sections[0].steps[1].detail, "1 MIN")
    }

    /// AMA-2390 — multi-station circuit keeps outer iterations as ROUNDS (Library /
    /// Apple Workout Repeat×N parity), not one "N SETS" band per station.
    func testCircuitRepeatBandsAsRoundsNotPerStationSets() throws {
        let json = """
        {
          "title": "Bike ski row",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            {
              "kind": "repeat",
              "reps": 8,
              "intervals": [
                { "kind": "work", "name": "Assault Bike", "seconds": 180 },
                { "kind": "work", "name": "Ski Erg", "seconds": 180 },
                { "kind": "work", "name": "Rowing Machine", "seconds": 180 },
                { "kind": "work", "name": "Spin / Indoor Bike", "seconds": 180 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        XCTAssertEqual(sections.count, 1, "Circuit must be one band, not four")
        XCTAssertEqual(sections[0].band, "Circuit")
        XCTAssertEqual(sections[0].tag, "8 ROUNDS")
        XCTAssertEqual(
            sections[0].steps.map(\.title),
            ["Assault Bike", "Ski Erg", "Rowing Machine", "Spin / Indoor Bike"]
        )
        XCTAssertEqual(sections[0].steps.map(\.detail), ["3 MIN", "3 MIN", "3 MIN", "3 MIN"])
        XCTAssertFalse(
            sections.flatMap(\.steps).contains { $0.title.localizedCaseInsensitiveContains("Work interval") },
            "Must not fan rounds into per-station Work intervals ×8"
        )
        XCTAssertFalse(sections.contains { $0.tag?.contains("SETS") == true })
    }

    /// AMA-2390 — circuit trailing rest must surface as a chip (not silently drop).
    func testCircuitRepeatRestPinsToLastStation() throws {
        let json = """
        {
          "title": "Bike ski row repeats",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            {
              "kind": "repeat",
              "reps": 6,
              "intervals": [
                { "kind": "work", "name": "Assault Bike", "seconds": 180 },
                { "kind": "work", "name": "Ski Erg", "seconds": 180 },
                { "kind": "work", "name": "Rowing Machine", "seconds": 180 },
                { "kind": "work", "name": "Spin / Indoor Bike", "seconds": 180 },
                { "kind": "rest", "seconds": 60 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].tag, "6 ROUNDS")
        XCTAssertEqual(sections[0].steps.last?.title, "Spin / Indoor Bike")
        XCTAssertEqual(sections[0].steps.last?.restChip, "REST 60S")
    }

    func testMobilityDurationTagIgnoresRepsDetails() throws {
        let json = """
        {
          "title": "Reps mobility",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            { "kind": "work", "name": "Jump Rope", "reps": 50 }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        XCTAssertEqual(sections.map(\.band), ["Mobility prep"])
        XCTAssertNil(sections[0].tag, "\"50 reps\" must not parse as seconds for ~N MIN")
    }

    func testMobilityRepeatEmitsOneRowPerRepForDurationTag() throws {
        let json = """
        {
          "title": "Mobility x3",
          "sportType": "traditionalStrengthTraining",
          "intervals": [
            {
              "kind": "repeat",
              "reps": 3,
              "intervals": [
                { "kind": "work", "name": "Jump Rope", "seconds": 60 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let sections = WorkoutKitPlanStepSummary.sections(from: json)
        XCTAssertEqual(sections.map(\.band), ["Mobility prep"])
        XCTAssertEqual(sections[0].steps.map(\.title), ["Jump Rope", "Jump Rope", "Jump Rope"])
        XCTAssertEqual(sections[0].tag, "~3 MIN")
    }

    func testMapperProviderForwardsDeliveryPrefs() async throws {
        let api = MockAPIService()
        api.fetchWorkoutBlocksJSONResult = .success([
            "title": "Strength",
            "blocks": [["name": "A", "exercises": [["name": "Squat", "reps": 8]]]]
        ])
        let fixture = """
        {"title":"Strength","sportType":"traditionalStrengthTraining","intervals":[{"kind":"work","name":"Squat","reps":8}]}
        """
        api.mapToWorkoutKitResult = .success(Data(fixture.utf8))
        let prefs = AppleWatchDeliveryPrefs.dogfood.deliveryPrefsDictionary
        let provider = MapperWorkoutKitPlanProvider(api: api, deliveryPrefs: prefs)
        _ = try await provider.fetchMapperPlanJSON(for: Workout(
            id: "w1",
            name: "Strength",
            sport: .strength,
            duration: 600,
            intervals: [],
            source: .manual
        ))
        XCTAssertTrue(api.mapToWorkoutKitCalled)
        XCTAssertEqual(api.lastMapToWorkoutKitDeliveryPrefs?["exercise_end"] as? String, "tap")
        XCTAssertEqual(api.lastMapToWorkoutKitDeliveryPrefs?["rest_mode"] as? String, "timed")
    }

    func testMapperProviderUsesDerivedPlanWithoutRefetch() async throws {
        let api = MockAPIService()
        api.fetchWorkoutBlocksJSONResult = .failure(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "should not fetch"])
        )
        let derived: [String: Any] = [
            "title": "Strength",
            "blocks": [
                [
                    "type": "warmup",
                    "enrichment_kind": "session_warmup",
                    "exercises": [["name": "Jump Rope"]]
                ] as [String: Any]
            ]
        ]
        let fixture = """
        {"title":"Strength","sportType":"traditionalStrengthTraining","intervals":[{"kind":"work","name":"Jump Rope"}]}
        """
        api.mapToWorkoutKitResult = .success(Data(fixture.utf8))
        let provider = MapperWorkoutKitPlanProvider(
            api: api,
            deliveryPrefs: nil,
            planBlocksJSON: derived
        )
        _ = try await provider.fetchMapperPlanJSON(for: Workout(
            id: "w1",
            name: "Strength",
            sport: .strength,
            duration: 600,
            intervals: [],
            source: .manual
        ))
        XCTAssertNil(api.lastFetchWorkoutBlocksJSONWorkoutId)
        XCTAssertTrue(api.mapToWorkoutKitCalled)
        XCTAssertNotNil(api.lastMapToWorkoutKitBlocks?["blocks"])
    }
}
