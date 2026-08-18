//
//  WorkoutKitPlanMetaTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2351 — composition preview copy + JSON meta decode.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutKitPlanMetaTests: XCTestCase {
    func testMetaDefaultsWhenFieldsMissing() {
        let data = Data(#"""
        {"title":"X","sportType":"running","intervals":[]}
        """#.utf8)
        let meta = WorkoutKitPlanMeta(fromMapperJSON: data)
        XCTAssertEqual(meta.composition, "custom")
        XCTAssertEqual(meta.compositionEffective, "custom")
        XCTAssertEqual(meta.routingReason, "legacy_unspecified")
    }

    func testNativeWarmupDisplayNameDecodesFromMapperJSON() {
        let data = Data("""
        {
          "title": "Ski Erg opener",
          "sportType": "traditionalStrengthTraining",
          "warmup": {
            "goal": { "kind": "time", "seconds": 300 },
            "displayName": "Ski Erg"
          },
          "intervals": [{ "kind": "warmup", "seconds": 300 }]
        }
        """.utf8)
        XCTAssertEqual(WorkoutKitPlanNativeWarmup.displayName(from: data), "Ski Erg")
    }

    func testNativeWarmupDisplayNameIgnoresBlankStrings() {
        let data = Data("""
        {
          "title": "Blank warmup",
          "sportType": "traditionalStrengthTraining",
          "warmup": { "displayName": "   " },
          "intervals": [{ "kind": "warmup", "seconds": 300 }]
        }
        """.utf8)
        XCTAssertNil(WorkoutKitPlanNativeWarmup.displayName(from: data))
    }

    func testCompositionLineHumanizesStrengthSets() {
        let meta = WorkoutKitPlanMeta(
            composition: "custom",
            compositionEffective: "custom",
            routingReason: "strength_sets"
        )
        let line = WorkoutKitRoutingCopy.compositionLine(meta: meta)
        XCTAssertTrue(line.contains("custom"))
        XCTAssertTrue(line.localizedCaseInsensitiveContains("strength"))
    }
}

@MainActor
final class WorkoutKitMapperCutoverTests: XCTestCase {
    func testHandoffDoesNotUseWorkoutKitConverterInterpretation() async {
        // Cutover guard: Start path saves mapper JSON only — no convertToWKPlanDTO.
        let saver = MockWorkoutKitSaverForCutover()
        let provider = StubPlanProviderForCutover()
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReaderCutover(),
            workoutKitSaver: .injected(saver),
            planProvider: provider
        )
        let workout = Workout(
            name: "Cutover",
            sport: .strength,
            duration: 600,
            intervals: [
                .reps(sets: 3, reps: 8, name: "Squat", load: nil, restSec: 90, followAlongUrl: nil)
            ],
            source: .manual
        )
        let result = await service.handoff(workout: workout)
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(saver.saveCount, 1)
        XCTAssertEqual(result.compositionLine?.contains("strength"), true)
    }
}

@MainActor
private final class MockWorkoutKitSaverForCutover: WorkoutKitSaving, @unchecked Sendable {
    var saveCount = 0
    func saveMapperPlanJSON(_ data: Data) async throws {
        saveCount += 1
        _ = data
    }
}

private final class StubPlanProviderForCutover: WorkoutKitPlanProviding, @unchecked Sendable {
    private(set) var fetchCount = 0
    func fetchMapperPlanJSON(for workout: Workout) async throws -> Data {
        fetchCount += 1
        _ = workout
        return Data(
            #"""
            {"title":"Cutover","sportType":"strengthTraining","composition":"custom","composition_effective":"custom","routing_reason":"strength_sets","intervals":[{"kind":"reps","reps":8,"name":"Squat"}]}
            """#.utf8
        )
    }
}

@MainActor
private struct MockPairingReaderCutover: AppleWatchPairingReading {
    func pairingReadForCopy() -> AppleWatchPairingRead { .unknown }
}
