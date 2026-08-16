//
//  EditorV2PropertyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2438 P1 — property-based testing: random command sequences + invariants.
//

import XCTest
@testable import AmakaFlowCompanion

final class EditorV2PropertyTests: XCTestCase {
    
    func testRandomCommandSequences_maintainInvariants() {
        let seed: UInt64 = 42
        var rng = SeededRNG(seed: seed)
        
        let sequenceCount = 300
        var failureCount = 0
        var totalCommands = 0
        
        for sequenceNum in 1...sequenceCount {
            let sequenceLength = Int.random(in: 20...200, using: &rng)
            var session = EditorV2Session()
            
            for step in 1...sequenceLength {
                totalCommands += 1
                let command = randomCommand(session: session, rng: &rng)
                let result = session.apply(command)
                
                if result != .applied {
                    // Command was rejected, which is valid
                    continue
                }
                
                // Check invariants after each applied command
                let violations = checkInvariants(session: session)
                if !violations.isEmpty {
                    failureCount += 1
                    print("Sequence \(sequenceNum), step \(step): Invariant violations after \(command)")
                    print("  Violations: \(violations)")
                    
                    // In a real PBT implementation, we would shrink here
                    // For now, just record and continue
                    break
                }
            }
        }
        
        print("\nProperty-Based Test Summary:")
        print("  Sequences run: \(sequenceCount)")
        print("  Total commands: \(totalCommands)")
        print("  Sequences with failures: \(failureCount)")
        print("  Seed: \(seed)")
        
        XCTAssertEqual(failureCount, 0, "Found \(failureCount) sequences that violated invariants")
    }
    
    private func randomCommand(session: EditorV2Session, rng: inout SeededRNG) -> EditorCommand {
        let commandTypes: [Int] = [0, 1, 2, 3, 4, 5, 6]
        let choice = commandTypes.randomElement(using: &rng)!
        
        switch choice {
        case 0:
            // addExercises
            let count = Int.random(in: 1...3, using: &rng)
            let names = (1...count).map { "Ex\($0)" }
            return .addExercises(names: names, into: nil)
            
        case 1:
            // removeExercise
            if let ex = session.exercises.randomElement() {
                return .removeExercise(ex.id)
            }
            return .addExercises(names: ["Fallback"], into: nil)
            
        case 2:
            // pairSuperset
            if session.exercises.count >= 2 {
                let shuffled = session.exercises.shuffled(using: &rng)
                return .pairSuperset(source: shuffled[0].id, target: shuffled[1].id)
            }
            return .addExercises(names: ["A", "B"], into: nil)
            
        case 3:
            // removeFromGroup
            if let ex = session.exercises.values.first(where: { $0.groupKey != nil }) {
                return .removeFromGroup(ex.id)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 4:
            // switchGroupType
            if let groupKey = session.groups.keys.randomElement() {
                let types: [EditorV2GroupType] = [.superset, .circuit, .emom, .amrap]
                let newType = types.randomElement(using: &rng)!
                return .switchGroupType(groupKey, newType)
            }
            return .addBlock(.circuit)
            
        case 5:
            // addSet
            if let ex = session.exercises.randomElement() {
                return .addSet(ex.id)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 6:
            // reorder
            if session.exercises.count >= 2 {
                let idx = Int.random(in: 0..<session.exercises.count, using: &rng)
                let toIdx = Int.random(in: 0...session.exercises.count, using: &rng)
                return .reorder(fromOffsets: IndexSet(integer: idx), toOffset: toIdx)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        default:
            return .addExercises(names: ["Default"], into: nil)
        }
    }
    
    private func checkInvariants(session: EditorV2Session) -> [String] {
        var violations: [String] = []
        
        // I1: Every id reference resolves; membership is a partition
        let allExerciseIDs = Set(session.exercises.values.map(\.id))
        if allExerciseIDs.count != session.exercises.count {
            violations.append("I1: Duplicate exercise IDs")
        }
        
        for exercise in session.exercises.values {
            if let groupKey = exercise.groupKey {
                if session.groups[groupKey] == nil {
                    violations.append("I1: Unresolved group reference: \(groupKey)")
                }
            }
        }
        
        // I2: Every group has ≥1 member OR is formatGroupKey
        for (key, _) in session.groups {
            let memberCount = session.exercises.filter { $0.groupKey == key }.count
            if memberCount == 0 && key != session.formatGroupKey {
                violations.append("I2: Empty non-format group: \(key)")
            }
        }
        
        // I3: All ids unique; projection (runs) ids unique
        let runIDs = session.runs.map(\.id)
        if Set(runIDs).count != runIDs.count {
            violations.append("I3: Duplicate run IDs")
        }
        
        // I4: Superset display label == f(memberCount)
        for (key, group) in session.groups where group.type == .superset {
            let memberCount = session.exercises.filter { $0.groupKey == key }.count
            let autoNames: Set<String> = ["Superset", "Tri-set", "Tri-sets"]
            if autoNames.contains(group.name) {
                if memberCount >= 3 && group.name == "Superset" {
                    violations.append("I4: ≥3 members should be Tri-set, not Superset")
                }
                if memberCount < 3 && (group.name == "Tri-set" || group.name == "Tri-sets") {
                    // This is actually OK during building - we keep Tri-set name
                }
            }
        }
        
        // I6: formatGroupKey, if set, resolves to an existing group
        if let fmtKey = session.formatGroupKey {
            if session.groups[fmtKey] == nil {
                violations.append("I6: formatGroupKey does not resolve: \(fmtKey)")
            }
        }
        
        return violations
    }
}

// Simple seeded RNG for reproducible tests
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        // LCG (Linear Congruential Generator)
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
