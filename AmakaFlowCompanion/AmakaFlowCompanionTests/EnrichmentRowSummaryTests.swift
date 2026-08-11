//
//  EnrichmentRowSummaryTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2408 F1 — golden fixtures per scaling-ladder rung + SKIPPED fuzz.
//

import XCTest
@testable import AmakaFlowCompanion

final class EnrichmentRowSummaryTests: XCTestCase {

    // MARK: Warm-ups ladder

    func testWarmupsOffReturnsNil() throws {
        let ramp = PerExerciseRamp(
            exerciseRef: "Incline Smith",
            enabled: true,
            sets: [try RampSet(kind: .reps, value: 8), try RampSet(kind: .reps, value: 5)]
        )
        XCTAssertNil(EnrichmentRowSummary.warmups(
            isOn: false,
            candidateNames: ["Incline Smith"],
            ramps: [ramp]
        ))
    }

    func testWarmupsN0NoRampsYet() {
        XCTAssertEqual(
            EnrichmentRowSummary.warmups(
                isOn: true,
                candidateNames: ["A", "B", "C"],
                ramps: []
            ),
            EnrichmentRowSummary.noRampsYet
        )
        XCTAssertEqual(
            EnrichmentRowSummary.warmups(
                isOn: true,
                candidateNames: ["A", "B"],
                ramps: [PerExerciseRamp(exerciseRef: "A", enabled: false, sets: [])]
            ),
            EnrichmentRowSummary.noRampsYet
        )
    }

    func testWarmupsN1() throws {
        let ramp = PerExerciseRamp(
            exerciseRef: "Incline Smith",
            enabled: true,
            sets: [try RampSet(kind: .reps, value: 8), try RampSet(kind: .reps, value: 5)]
        )
        let candidates = (1...7).map { "Ex\($0)" }
        var names = candidates
        names[0] = "Incline Smith"
        XCTAssertEqual(
            EnrichmentRowSummary.warmups(isOn: true, candidateNames: names, ramps: [ramp]),
            "INCLINE SMITH · RAMP ×2 · 1 OF 7"
        )
    }

    func testWarmupsN2() throws {
        let ramps = [
            PerExerciseRamp(
                exerciseRef: "Incline Smith",
                enabled: true,
                sets: [try RampSet(kind: .reps, value: 8)]
            ),
            PerExerciseRamp(
                exerciseRef: "Row",
                enabled: true,
                sets: [try RampSet(kind: .reps, value: 5)]
            )
        ]
        let candidates = ["Incline Smith", "Row", "Curl", "Press", "Fly", "Raise", "Squat"]
        XCTAssertEqual(
            EnrichmentRowSummary.warmups(isOn: true, candidateNames: candidates, ramps: ramps),
            "INCLINE SMITH + 1 MORE · 2 OF 7"
        )
    }

    func testWarmupsN3() throws {
        let ramps = (0..<3).map { i in
            PerExerciseRamp(
                exerciseRef: i == 0 ? "Incline Smith" : "Ex\(i)",
                enabled: true,
                sets: [try! RampSet(kind: .reps, value: 5)]
            )
        }
        let candidates = (0..<7).map { $0 == 0 ? "Incline Smith" : "Ex\($0)" }
        XCTAssertEqual(
            EnrichmentRowSummary.warmups(isOn: true, candidateNames: candidates, ramps: ramps),
            "INCLINE SMITH + 2 MORE · 3 OF 7"
        )
    }

    func testWarmupsN4() throws {
        let ramps = (0..<4).map {
            PerExerciseRamp(
                exerciseRef: "Ex\($0)",
                enabled: true,
                sets: [try! RampSet(kind: .reps, value: 5)]
            )
        }
        let candidates = (0..<20).map { "Ex\($0)" }
        XCTAssertEqual(
            EnrichmentRowSummary.warmups(isOn: true, candidateNames: candidates, ramps: ramps),
            "CUSTOM RAMPS · 4 OF 20"
        )
    }

    func testWarmups12Of20() throws {
        let ramps = (0..<12).map {
            PerExerciseRamp(
                exerciseRef: "Ex\($0)",
                enabled: true,
                sets: [try! RampSet(kind: .reps, value: 5)]
            )
        }
        let candidates = (0..<20).map { "Ex\($0)" }
        XCTAssertEqual(
            EnrichmentRowSummary.warmups(isOn: true, candidateNames: candidates, ramps: ramps),
            "CUSTOM RAMPS · 12 OF 20"
        )
    }

    func testWarmupsAll20() throws {
        let candidates = (0..<20).map { "Ex\($0)" }
        let ramps = candidates.map {
            PerExerciseRamp(
                exerciseRef: $0,
                enabled: true,
                sets: [try! RampSet(kind: .reps, value: 5)]
            )
        }
        XCTAssertEqual(
            EnrichmentRowSummary.warmups(isOn: true, candidateNames: candidates, ramps: ramps),
            "CUSTOM RAMPS · ALL 20"
        )
    }

    // MARK: Sequences

    func testSequenceOffReturnsNil() throws {
        let activities = [
            EnrichmentActivity(name: "Jump Rope", goal: try ActivityGoal(kind: .open, value: nil))
        ]
        XCTAssertNil(EnrichmentRowSummary.sequence(isOn: false, activities: activities))
    }

    func testSequenceN1() throws {
        let activities = [
            EnrichmentActivity(name: "Jump Rope", goal: try ActivityGoal(kind: .open, value: nil))
        ]
        XCTAssertEqual(
            EnrichmentRowSummary.sequence(isOn: true, activities: activities),
            "JUMP ROPE OPEN · 1 STEP"
        )
    }

    func testSequenceN2() throws {
        let activities = [
            EnrichmentActivity(name: "Ski Erg", goal: try ActivityGoal(kind: .distance, value: 500)),
            EnrichmentActivity(name: "Jump Rope", goal: try ActivityGoal(kind: .open, value: nil))
        ]
        XCTAssertEqual(
            EnrichmentRowSummary.sequence(isOn: true, activities: activities),
            "SKI ➜ ROPE · 2 STEPS"
        )
    }

    func testSequenceN3() throws {
        let activities = [
            EnrichmentActivity(name: "Ski Erg", goal: try ActivityGoal(kind: .distance, value: 500)),
            EnrichmentActivity(name: "Jump Rope", goal: try ActivityGoal(kind: .open, value: nil)),
            EnrichmentActivity(name: "Assault Bike", goal: try ActivityGoal(kind: .time, value: 120))
        ]
        XCTAssertEqual(
            EnrichmentRowSummary.sequence(isOn: true, activities: activities),
            "SKI ➜ ROPE ➜ BIKE · 3 STEPS"
        )
    }

    func testSequenceN4Plus() throws {
        let activities = (0..<4).map { i in
            EnrichmentActivity(
                name: "Step \(i)",
                goal: try! ActivityGoal(kind: .time, value: 180)
            )
        }
        // 4 × 180s = 720s → 12 min
        XCTAssertEqual(
            EnrichmentRowSummary.sequence(isOn: true, activities: activities),
            "4 STEPS · ≈12 MIN"
        )
    }

    // MARK: SKIPPED unrepresentable

    func testSkippedUnrepresentableFuzz() throws {
        for seed in 0..<200 {
            var generator = SeededGenerator(seed: UInt64(seed))
            let candidateCount = Int.random(in: 0...24, using: &generator)
            let candidates = (0..<candidateCount).map { "Exercise \($0)" }
            var ramps: [PerExerciseRamp] = []
            for name in candidates where Bool.random(using: &generator) {
                let enabled = Bool.random(using: &generator)
                let setCount = enabled ? Int.random(in: 0...4, using: &generator) : 0
                let sets = (0..<setCount).compactMap { _ in
                    try? RampSet(kind: .reps, value: Int.random(in: 1...12, using: &generator))
                }
                ramps.append(PerExerciseRamp(exerciseRef: name, enabled: enabled, sets: sets))
            }
            let isOn = Bool.random(using: &generator)
            let line = EnrichmentRowSummary.warmups(
                isOn: isOn,
                candidateNames: candidates,
                ramps: ramps
            )
            if let line {
                XCTAssertFalse(
                    line.uppercased().contains("SKIPPED"),
                    "fuzz seed \(seed) produced SKIPPED: \(line)"
                )
            }

            let activities = (0..<Int.random(in: 0...6, using: &generator)).map { i in
                EnrichmentActivity(
                    name: "Act \(i)",
                    goal: try! ActivityGoal(kind: .open, value: nil)
                )
            }
            let seq = EnrichmentRowSummary.sequence(
                isOn: Bool.random(using: &generator),
                activities: activities
            )
            if let seq {
                XCTAssertFalse(seq.uppercased().contains("SKIPPED"), "seq fuzz seed \(seed): \(seq)")
            }
        }
    }

    func testWarmupExerciseTagNeverSaysSkipped() {
        XCTAssertFalse(
            WorkoutEnrichmentPushCopy.warmupExerciseTag(name: "Leg Press", ramp: nil)
                .contains("SKIPPED")
        )
    }
}

/// Deterministic RNG for fuzz tests.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
