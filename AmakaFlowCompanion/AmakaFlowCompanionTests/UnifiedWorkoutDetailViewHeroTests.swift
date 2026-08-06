//
//  UnifiedWorkoutDetailViewHeroTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2381 Task 9 — hero pill rounds use max across work blocks, not sum.
//

import XCTest
@testable import AmakaFlowCompanion

final class UnifiedWorkoutDetailViewHeroTests: XCTestCase {
    private func makeBlock(structure: BlockStructure, rounds: Int) -> Block {
        Block(
            label: nil,
            structure: structure,
            rounds: rounds,
            exercises: [
                Exercise(
                    name: "Test move",
                    canonicalName: nil,
                    sets: 1,
                    reps: "10",
                    durationSeconds: nil,
                    load: nil,
                    restSeconds: nil,
                    distance: nil,
                    notes: nil,
                    focus: nil,
                    supersetGroup: nil
                )
            ]
        )
    }

    func testHeroRoundCountUsesMaxNotSum() {
        let blocks = [
            makeBlock(structure: .emom, rounds: 4),
            makeBlock(structure: .circuit, rounds: 3),
        ]
        XCTAssertEqual(UnifiedWorkoutDetailView.heroRoundCount(for: blocks), 4)
    }
}
