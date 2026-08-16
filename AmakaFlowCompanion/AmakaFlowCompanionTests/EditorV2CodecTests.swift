//
//  EditorV2CodecTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2438 P3 — Structure codec round-trip tests.
//

import XCTest
@testable import AmakaFlow

final class EditorV2CodecTests: XCTestCase {
    
    // MARK: - Round-trip law
    
    func testRoundTripLaw_normalizePreserved() {
        var session = EditorV2Session()
        _ = session.apply(.addExercises(names: ["A", "B", "C"], into: nil))
        
        let blocks = session.encodeToBlocks()
        let decoded = EditorV2Session.decodeFromBlocks(title: session.title, blocks: blocks)
        
        // Law: decode(encode(s)) == normalize(s)
        XCTAssertEqual(decoded.order.count, session.order.count)
        XCTAssertEqual(decoded.exercises.count, session.exercises.count)
        XCTAssertEqual(decoded.groups.count, session.groups.count)
    }
    
    // MARK: - Warm-up survival
    
    func testWarmupSurvivesReload() {
        var session = EditorV2Session()
        let warmupKey = UUID().uuidString
        
        let ex1 = EditorV2Exercise(name: "Jump rope")
        session.exercises = [ex1.id: ex1]
        session.groups[warmupKey] = EditorV2Group(
            id: warmupKey,
            type: .warmup,
            name: "Warm-up",
            memberIDs: [ex1.id]
        )
        session.order = [.group(warmupKey)]
        
        let blocks = session.encodeToBlocks()
        let decoded = EditorV2Session.decodeFromBlocks(title: "Test", blocks: blocks)
        
        // Warm-up must not become circuit or straight
        let firstGroup = decoded.groups.values.first
        XCTAssertEqual(firstGroup?.type, .warmup, "Warm-up must survive reload")
    }
    
    func testCooldownSurvivesReload() {
        var session = EditorV2Session()
        let cooldownKey = UUID().uuidString
        
        let ex1 = EditorV2Exercise(name: "Stretch")
        session.exercises = [ex1.id: ex1]
        session.groups[cooldownKey] = EditorV2Group(
            id: cooldownKey,
            type: .cooldown,
            name: "Cooldown",
            memberIDs: [ex1.id]
        )
        session.order = [.group(cooldownKey)]
        
        let blocks = session.encodeToBlocks()
        let decoded = EditorV2Session.decodeFromBlocks(title: "Test", blocks: blocks)
        
        // Cooldown must not become straight
        let firstGroup = decoded.groups.values.first
        XCTAssertEqual(firstGroup?.type, .cooldown, "Cooldown must survive reload")
    }
    
    // MARK: - Time cap survival
    
    func testAMRAPTimeCapSurvives() {
        var session = EditorV2Session()
        let amrapKey = UUID().uuidString
        
        let ex1 = EditorV2Exercise(name: "Burpees")
        session.exercises = [ex1.id: ex1]
        session.groups[amrapKey] = EditorV2Group(
            id: amrapKey,
            type: .amrap,
            name: "AMRAP",
            config: EditorV2GroupConfig(rounds: 1, capMinutes: 20),
            memberIDs: [ex1.id]
        )
        session.order = [.group(amrapKey)]
        
        let blocks = session.encodeToBlocks()
        XCTAssertEqual(blocks.first?.timeCapSec, 20 * 60, "AMRAP cap must be encoded as seconds")
        
        let decoded = EditorV2Session.decodeFromBlocks(title: "Test", blocks: blocks)
        let firstGroup = decoded.groups.values.first
        XCTAssertEqual(firstGroup?.config.capMinutes, 20, "AMRAP cap must survive reload")
    }
    
    func testForTimeCapSurvives() {
        var session = EditorV2Session()
        let fortimeKey = UUID().uuidString
        
        let ex1 = EditorV2Exercise(name: "Thrusters")
        session.exercises = [ex1.id: ex1]
        session.groups[fortimeKey] = EditorV2Group(
            id: fortimeKey,
            type: .fortime,
            name: "For Time",
            config: EditorV2GroupConfig(rounds: 1, capMinutes: 15),
            memberIDs: [ex1.id]
        )
        session.order = [.group(fortimeKey)]
        
        let blocks = session.encodeToBlocks()
        XCTAssertEqual(blocks.first?.timeCapSec, 15 * 60, "For-time cap must be encoded")
        
        let decoded = EditorV2Session.decodeFromBlocks(title: "Test", blocks: blocks)
        let firstGroup = decoded.groups.values.first
        XCTAssertEqual(firstGroup?.type, .fortime, "For-time must survive reload")
        XCTAssertEqual(firstGroup?.config.capMinutes, 15, "For-time cap must survive")
    }
    
    // MARK: - Mixed structures
    
    func testMixedStructuresRoundTrip() {
        var session = EditorV2Session()
        
        // Warmup
        let warmupKey = UUID().uuidString
        let warmupEx = EditorV2Exercise(name: "Jump rope")
        session.groups[warmupKey] = EditorV2Group(
            id: warmupKey,
            type: .warmup,
            memberIDs: [warmupEx.id]
        )
        session.exercises[warmupEx.id] = warmupEx
        
        // Superset
        let ssKey = UUID().uuidString
        let ssEx1 = EditorV2Exercise(name: "Squat")
        let ssEx2 = EditorV2Exercise(name: "Press")
        session.groups[ssKey] = EditorV2Group(
            id: ssKey,
            type: .superset,
            letter: "A",
            memberIDs: [ssEx1.id, ssEx2.id]
        )
        session.exercises[ssEx1.id] = ssEx1
        session.exercises[ssEx2.id] = ssEx2
        
        // AMRAP with cap
        let amrapKey = UUID().uuidString
        let amrapEx = EditorV2Exercise(name: "Burpees")
        session.groups[amrapKey] = EditorV2Group(
            id: amrapKey,
            type: .amrap,
            config: EditorV2GroupConfig(rounds: 1, capMinutes: 12),
            memberIDs: [amrapEx.id]
        )
        session.exercises[amrapEx.id] = amrapEx
        
        // Cooldown
        let cooldownKey = UUID().uuidString
        let cooldownEx = EditorV2Exercise(name: "Stretch")
        session.groups[cooldownKey] = EditorV2Group(
            id: cooldownKey,
            type: .cooldown,
            memberIDs: [cooldownEx.id]
        )
        session.exercises[cooldownEx.id] = cooldownEx
        
        session.order = [
            .group(warmupKey),
            .group(ssKey),
            .group(amrapKey),
            .group(cooldownKey)
        ]
        
        let blocks = session.encodeToBlocks()
        XCTAssertEqual(blocks.count, 4)
        
        let decoded = EditorV2Session.decodeFromBlocks(title: "Mixed", blocks: blocks)
        
        // Verify all types survived
        let types = decoded.groups.values.map(\.type).sorted { $0.rawValue < $1.rawValue }
        XCTAssertTrue(types.contains(.warmup))
        XCTAssertTrue(types.contains(.superset))
        XCTAssertTrue(types.contains(.amrap))
        XCTAssertTrue(types.contains(.cooldown))
        
        // Verify AMRAP cap
        let amrapGroup = decoded.groups.values.first(where: { $0.type == .amrap })
        XCTAssertEqual(amrapGroup?.config.capMinutes, 12)
    }
    
    // MARK: - Pinned empty group
    
    func testPinnedEmptyGroupRoundTrip() {
        var session = EditorV2Session()
        let emomKey = "fmt"
        session.groups[emomKey] = EditorV2Group(
            id: emomKey,
            type: .emom,
            memberIDs: []
        )
        session.formatGroupKey = emomKey
        session.order = [.group(emomKey)]
        
        let blocks = session.encodeToBlocks()
        
        // Empty format group should still be encoded
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks.first?.exercises.isEmpty ?? false)
    }
}
