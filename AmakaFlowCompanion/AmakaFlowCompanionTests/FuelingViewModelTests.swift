//
//  FuelingViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for FuelingViewModel types and ProteinNudgeResponse (AMA-1293).
//
//  Tests the FuelingStatus enum, response Codable models, and nudge logic
//  without creating @MainActor ViewModel instances (following existing test patterns).
//

import XCTest
@testable import AmakaFlowCompanion

final class FuelingViewModelTests: XCTestCase {

    // MARK: - FuelingStatus Enum Tests

    func testFuelingStatusFromGreen() {
        let status = FuelingStatus(from: "green")
        XCTAssertEqual(status, .green)
    }

    func testFuelingStatusFromYellow() {
        let status = FuelingStatus(from: "yellow")
        XCTAssertEqual(status, .yellow)
    }

    func testFuelingStatusFromRed() {
        let status = FuelingStatus(from: "red")
        XCTAssertEqual(status, .red)
    }

    func testFuelingStatusFromUnknown() {
        let status = FuelingStatus(from: "banana")
        XCTAssertEqual(status, .unknown)
    }

    func testFuelingStatusIcons() {
        XCTAssertEqual(FuelingStatus.green.icon, "checkmark.circle.fill")
        XCTAssertEqual(FuelingStatus.yellow.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(FuelingStatus.red.icon, "xmark.circle.fill")
        XCTAssertEqual(FuelingStatus.unknown.icon, "questionmark.circle")
    }

    func testFuelingStatusColors() {
        // Just verify they don't crash — Color equality is tricky
        _ = FuelingStatus.green.color
        _ = FuelingStatus.yellow.color
        _ = FuelingStatus.red.color
        _ = FuelingStatus.unknown.color
    }

    // MARK: - FuelingStatusResponse Codable Tests

    func testFuelingStatusResponseDecoding() throws {
        let json = """
        {
            "status": "green",
            "protein_pct": 85.3,
            "calories_pct": 72.1,
            "hydration_pct": 65.0,
            "message": "Well fueled"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(FuelingStatusResponse.self, from: json)

        XCTAssertEqual(response.status, "green")
        XCTAssertEqual(response.proteinPct, 85.3)
        XCTAssertEqual(response.caloriesPct, 72.1)
        XCTAssertEqual(response.hydrationPct, 65.0)
        XCTAssertEqual(response.message, "Well fueled")
    }

    func testFuelingStatusResponseRedDecoding() throws {
        let json = """
        {
            "status": "red",
            "protein_pct": 20.0,
            "calories_pct": 15.5,
            "hydration_pct": 30.0,
            "message": "Very low fuel"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(FuelingStatusResponse.self, from: json)

        XCTAssertEqual(response.status, "red")
        XCTAssertEqual(response.proteinPct, 20.0)
    }

    func testFuelingStatusResponseEquatable() {
        let a = FuelingStatusResponse(
            status: "green", proteinPct: 80, caloriesPct: 70,
            hydrationPct: 60, message: "Well fueled"
        )
        let b = FuelingStatusResponse(
            status: "green", proteinPct: 80, caloriesPct: 70,
            hydrationPct: 60, message: "Well fueled"
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - ProteinNudgeResponse Codable Tests

    func testProteinNudgeResponseDecoding() throws {
        let json = """
        {
            "should_nudge": true,
            "protein_current": 50,
            "protein_target": 120,
            "message": "You're at 50g of 120g protein"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(ProteinNudgeResponse.self, from: json)

        XCTAssertTrue(response.shouldNudge)
        XCTAssertEqual(response.proteinCurrent, 50)
        XCTAssertEqual(response.proteinTarget, 120)
    }

    func testProteinNudgeResponseNoNudge() throws {
        let json = """
        {
            "should_nudge": false,
            "protein_current": 90,
            "protein_target": 120,
            "message": "Great protein intake"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(ProteinNudgeResponse.self, from: json)

        XCTAssertFalse(response.shouldNudge)
        XCTAssertEqual(response.proteinCurrent, 90)
    }

    func testProteinNudgeResponseEquatable() {
        let a = ProteinNudgeResponse(
            shouldNudge: true, proteinCurrent: 50,
            proteinTarget: 120, message: "Eat more"
        )
        let b = ProteinNudgeResponse(
            shouldNudge: true, proteinCurrent: 50,
            proteinTarget: 120, message: "Eat more"
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - Encoding Round-Trip Tests

    func testFuelingStatusResponseRoundTrip() throws {
        let original = FuelingStatusResponse(
            status: "yellow", proteinPct: 55.5, caloriesPct: 45.2,
            hydrationPct: 70.0, message: "Keep fueling"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FuelingStatusResponse.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testProteinNudgeResponseRoundTrip() throws {
        let original = ProteinNudgeResponse(
            shouldNudge: true, proteinCurrent: 30,
            proteinTarget: 100, message: "70g to go"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProteinNudgeResponse.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
