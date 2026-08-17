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

    // AMA-2443: undo interleaved into random sequences — invariants must
    // hold after every step, whether it was a command or an undo.
    func testRandomCommandsInterleavedWithUndo_maintainInvariants() {
        let seed: UInt64 = 2443
        var rng = SeededRNG(seed: seed)

        let sequenceCount = 150
        var failureCount = 0

        for sequenceNum in 1...sequenceCount {
            let sequenceLength = Int.random(in: 20...120, using: &rng)
            var session = EditorV2Session()

            for step in 1...sequenceLength {
                // ~1 in 5 steps is an undo gesture instead of a command.
                if Int.random(in: 0..<5, using: &rng) == 0 {
                    _ = session.undo()
                } else {
                    let command = randomCommand(session: session, rng: &rng)
                    let result = session.apply(command)
                    if result != .applied { continue }
                }

                let violations = checkInvariants(session: session)
                if !violations.isEmpty {
                    failureCount += 1
                    print("Sequence \(sequenceNum), step \(step): violations \(violations)")
                    break
                }
            }
        }

        XCTAssertEqual(failureCount, 0,
            "Found \(failureCount) undo-interleaved sequences that violated invariants (seed \(seed))")
    }

    // AMA-2443: undo(n) restores the exact state n state-changing gestures
    // ago — walk the whole history back and compare snapshots.
    func testUndoN_restoresNthPriorState() {
        let seed: UInt64 = 99
        var rng = SeededRNG(seed: seed)
        var session = EditorV2Session()
        // History of states BEFORE each state-changing apply, oldest first.
        var history: [EditorV2Session] = []

        var applied = 0
        var attempts = 0
        while applied < 30 && attempts < 300 {
            attempts += 1
            let before = session
            let command = randomCommand(session: session, rng: &rng)
            let result = session.apply(command)
            if result == .applied && session != before {
                history.append(before)
                applied += 1
            }
        }
        XCTAssertGreaterThanOrEqual(applied, 20, "generator failed to produce enough state changes")

        // The stack caps at 50 — we applied ≤30, so every entry is present.
        while let expected = history.popLast() {
            XCTAssertTrue(session.undo(), "undo stack exhausted early")
            XCTAssertEqual(session.exercises, expected.exercises)
            XCTAssertEqual(session.order, expected.order)
            XCTAssertEqual(session.groups, expected.groups)
        }
        XCTAssertFalse(session.canUndo, "stack should be empty after full walk-back")
    }

    private func randomCommand(session: EditorV2Session, rng: inout SeededRNG) -> EditorCommand {
        let commandTypes: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
        let choice = commandTypes.randomElement(using: &rng)!
        
        switch choice {
        case 0:
            // addExercises — AMA-2443 slice 3: sometimes pick an existing group as destination
            let count = Int.random(in: 1...3, using: &rng)
            let names = (1...count).map { "Ex\($0)" }
            let into: String?
            if !session.groups.isEmpty, Int.random(in: 0..<4, using: &rng) == 0 {
                into = Array(session.groups.keys).randomElement(using: &rng)
            } else {
                into = nil
            }
            return .addExercises(names: names, into: into)
            
        case 1:
            // removeExercise
            let exs = Array(session.exercises.values)
            if !exs.isEmpty, let ex = exs.randomElement(using: &rng) {
                return .removeExercise(ex.id)
            }
            return .addExercises(names: ["Fallback"], into: nil)
            
        case 2:
            // pairSuperset
            if session.exercises.count >= 2 {
                let shuffled = Array(session.exercises.values).shuffled(using: &rng)
                return .pairSuperset(source: shuffled[0].id, target: shuffled[1].id)
            }
            return .addExercises(names: ["A", "B"], into: nil)
            
        case 3:
            // removeFromGroup
            let exs = Array(session.exercises.values)
            if let ex = exs.first(where: { $0.groupKey != nil }) {
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
            let exs = Array(session.exercises.values)
            if !exs.isEmpty, let ex = exs.randomElement(using: &rng) {
                return .addSet(ex.id)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 6:
            // reorder
            if session.order.count >= 2 {
                let idx = Int.random(in: 0..<session.order.count, using: &rng)
                let toIdx = Int.random(in: 0...session.order.count, using: &rng)
                return .reorder(fromOffsets: IndexSet(integer: idx), toOffset: toIdx)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 7:
            // setExerciseReps
            let exs = Array(session.exercises.values)
            if !exs.isEmpty, let ex = exs.randomElement(using: &rng) {
                let reps = Int.random(in: 5...20, using: &rng)
                return .setExerciseReps(ex.id, reps)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 8:
            // setExerciseSets
            let exs = Array(session.exercises.values)
            if !exs.isEmpty, let ex = exs.randomElement(using: &rng) {
                let sets = Int.random(in: 1...10, using: &rng)
                return .setExerciseSets(ex.id, sets)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 9:
            // setExerciseWeight
            let exs = Array(session.exercises.values)
            if !exs.isEmpty, let ex = exs.randomElement(using: &rng) {
                let weight = Double.random(in: 20.0...200.0, using: &rng)
                return .setExerciseWeight(ex.id, weight)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 10:
            // setExerciseRest
            let exs = Array(session.exercises.values)
            if !exs.isEmpty, let ex = exs.randomElement(using: &rng) {
                let rest = Int.random(in: 30...180, using: &rng)
                return .setExerciseRest(ex.id, rest)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 11:
            // setExerciseRepsRange
            let exs = Array(session.exercises.values)
            if !exs.isEmpty, let ex = exs.randomElement(using: &rng) {
                let lower = Int.random(in: 5...10, using: &rng)
                let upper = Int.random(in: lower...20, using: &rng)
                let range = RepsRange(low: lower, high: upper, qualifier: nil)
                return .setExerciseRepsRange(ex.id, range)
            }
            return .addExercises(names: ["Test"], into: nil)
            
        case 12:
            // setExerciseBodyweight
            let exs = Array(session.exercises.values)
            if !exs.isEmpty, let ex = exs.randomElement(using: &rng) {
                let isBodyweight = Bool.random(using: &rng)
                return .setExerciseBodyweight(ex.id, isBodyweight)
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
                } else if !(session.groups[groupKey]?.memberIDs.contains(exercise.id) ?? false) {
                    violations.append("I1: Exercise \(exercise.id) has groupKey \(groupKey) but group doesn't contain it")
                }
            } else {
                // Exercise has no groupKey, check it's not in any group
                for (key, group) in session.groups where group.memberIDs.contains(exercise.id) {
                    violations.append("I1: Exercise \(exercise.id) has no groupKey but is in group \(key)")
                }
            }
        }
        
        // I2: Every group has ≥1 member OR is formatGroupKey
        for (key, group) in session.groups {
            let memberCount = group.memberIDs.count
            if memberCount == 0 && key != session.formatGroupKey {
                violations.append("I2: Empty non-format group: \(key)")
            }
        }
        
        // I3: All ids unique; projection (runs) ids unique
        let runIDs = session.runs.map(\.id)
        if Set(runIDs).count != runIDs.count {
            violations.append("I3: Duplicate run IDs")
        }
        
        // I4: Superset display label == f(memberCount), except formatGroupKey while building
        for (key, group) in session.groups where group.type == .superset {
            // Skip formatGroupKey - it keeps target name while building
            if key == session.formatGroupKey {
                continue
            }
            
            let memberCount = group.memberIDs.count
            let autoNames: Set<String> = ["Superset", "Tri-set", "Tri-sets", "Giant set"]
            if autoNames.contains(group.name) {
                if memberCount >= 4 && group.name != "Giant set" {
                    violations.append("I4: ≥4 members should be Giant set, not \(group.name)")
                } else if memberCount == 3 && !["Tri-set", "Tri-sets"].contains(group.name) {
                    violations.append("I4: 3 members should be Tri-set, not \(group.name)")
                } else if memberCount == 2 && group.name != "Superset" {
                    violations.append("I4: 2 members should be Superset, not \(group.name)")
                }
            }
        }
        
        // I6: formatGroupKey, if set, resolves to an existing group
        if let fmtKey = session.formatGroupKey {
            if session.groups[fmtKey] == nil {
                violations.append("I6: formatGroupKey does not resolve: \(fmtKey)")
            }
        }
        
        // I7: D2 partition - all exercises are in exactly one place in order
        var seenInOrder = Set<String>()
        for row in session.order {
            switch row {
            case .group(let key):
                guard let group = session.groups[key] else {
                    violations.append("I7: order references nonexistent group \(key)")
                    continue
                }
                for memberID in group.memberIDs {
                    if seenInOrder.contains(memberID) {
                        violations.append("I7: Exercise \(memberID) appears twice in order")
                    }
                    seenInOrder.insert(memberID)
                }
            case .loose(let id):
                if seenInOrder.contains(id) {
                    violations.append("I7: Exercise \(id) appears twice in order")
                }
                seenInOrder.insert(id)
            }
        }
        for id in session.exercises.keys {
            if !seenInOrder.contains(id) {
                violations.append("I7: Exercise \(id) not in order")
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
