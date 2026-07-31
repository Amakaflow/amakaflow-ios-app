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
