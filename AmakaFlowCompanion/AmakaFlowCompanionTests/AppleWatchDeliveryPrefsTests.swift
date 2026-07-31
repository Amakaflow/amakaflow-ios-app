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

    func testPersistAndLiveSelection() {
        AppleWatchDeliveryPrefsStore.applyLiveSelection(restMode: .tap)
        XCTAssertEqual(AppleWatchDeliveryPrefsStore.current.restMode, .tap)
        XCTAssertTrue(AppleWatchDeliveryPrefsStore.hasConfigured)
        XCTAssertTrue(
            AppleWatchDeliveryPrefsStore.current.summaryLine.localizedCaseInsensitiveContains("tap")
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
        XCTAssertTrue(lines.contains { $0.contains("Squat") || $0.contains("Repeat") })
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
