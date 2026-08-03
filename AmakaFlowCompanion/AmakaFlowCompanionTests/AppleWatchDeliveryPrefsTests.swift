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
        XCTAssertEqual(sections[1].tag, "5 SETS")
        XCTAssertEqual(
            sections[1].steps.map(\.title),
            ["Warm-up set", "Warm-up set", "Working sets ×3"]
        )
        XCTAssertTrue(sections[1].steps.allSatisfy { $0.restChip == "REST · YOU END IT" })
        XCTAssertEqual(sections.flatMap(\.steps).map(\.number), [1, 2, 3, 4])
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
}
