//
//  RPEFeedbackViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for RPEFeedbackViewModel types and logic (AMA-1266)
//
//  Tests the RPE option values, muscle groups, and Codable models
//  without creating @MainActor ViewModel instances (following existing test patterns).
//

import XCTest
@testable import AmakaFlowCompanion

final class RPEFeedbackViewModelTests: XCTestCase {

    // MARK: - RPEOption Tests

    func testRPEOptionValues() {
        XCTAssertEqual(RPEOption.easy.rpeValue, 4)
        XCTAssertEqual(RPEOption.moderate.rpeValue, 6)
        XCTAssertEqual(RPEOption.hard.rpeValue, 8)
        XCTAssertEqual(RPEOption.crushed.rpeValue, 10)
    }

    func testRPEOptionLabels() {
        XCTAssertEqual(RPEOption.easy.label, "Easy")
        XCTAssertEqual(RPEOption.moderate.label, "Moderate")
        XCTAssertEqual(RPEOption.hard.label, "Hard")
        XCTAssertEqual(RPEOption.crushed.label, "Crushed")
    }

    func testRPEOptionEmojis() {
        for option in RPEOption.allCases {
            XCTAssertFalse(option.emoji.isEmpty, "\(option.label) should have an emoji")
        }
    }

    func testAllRPEOptionsExist() {
        XCTAssertEqual(RPEOption.allCases.count, 4)
    }

    func testRPEOptionIds() {
        // IDs must be unique for SwiftUI ForEach
        let ids = RPEOption.allCases.map { $0.id }
        XCTAssertEqual(Set(ids).count, 4, "All RPE option IDs should be unique")
    }

    func testRPEOptionRPEValueRange() {
        // All RPE values should be in 1-10 range
        for option in RPEOption.allCases {
            XCTAssertTrue((1...10).contains(option.rpeValue), "\(option.label) rpeValue \(option.rpeValue) should be 1-10")
        }
    }

    func testRPEOptionsOrderedByDifficulty() {
        let values = RPEOption.allCases.map { $0.rpeValue }
        // Values should be strictly increasing
        for i in 1..<values.count {
            XCTAssertGreaterThan(values[i], values[i - 1], "RPE values should increase with difficulty")
        }
    }

    // MARK: - MuscleGroup Tests

    func testMuscleGroupDisplayNames() {
        XCTAssertEqual(MuscleGroup.chest.displayName, "Chest")
        XCTAssertEqual(MuscleGroup.back.displayName, "Back")
        XCTAssertEqual(MuscleGroup.legs.displayName, "Legs")
        XCTAssertEqual(MuscleGroup.shoulders.displayName, "Shoulders")
        XCTAssertEqual(MuscleGroup.arms.displayName, "Arms")
        XCTAssertEqual(MuscleGroup.core.displayName, "Core")
    }

    func testAllMuscleGroupsExist() {
        XCTAssertEqual(MuscleGroup.allCases.count, 6)
    }

    func testMuscleGroupRawValues() {
        // Raw values should be lowercase for API compatibility
        for muscle in MuscleGroup.allCases {
            XCTAssertEqual(muscle.rawValue, muscle.rawValue.lowercased(),
                           "\(muscle.rawValue) should be lowercase")
        }
    }

    func testMuscleGroupIds() {
        let ids = MuscleGroup.allCases.map { $0.id }
        XCTAssertEqual(Set(ids).count, 6, "All muscle group IDs should be unique")
    }

    // MARK: - RPEFeedbackRequest Encoding Tests

    func testRPEFeedbackRequestEncoding() throws {
        let request = RPEFeedbackRequest(
            workoutId: "workout-123",
            rpe: 8,
            muscleSoreness: ["chest", "legs"],
            notes: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"workout_id\":\"workout-123\""))
        XCTAssertTrue(json.contains("\"rpe\":8"))
        XCTAssertTrue(json.contains("\"muscle_soreness\""))
        XCTAssertTrue(json.contains("chest"))
        XCTAssertTrue(json.contains("legs"))
    }

    func testRPEFeedbackRequestEncodingWithoutSoreness() throws {
        let request = RPEFeedbackRequest(
            workoutId: "workout-456",
            rpe: 4,
            muscleSoreness: nil,
            notes: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"workout_id\":\"workout-456\""))
        XCTAssertTrue(json.contains("\"rpe\":4"))
    }

    func testRPEFeedbackRequestEncodingWithNotes() throws {
        let request = RPEFeedbackRequest(
            workoutId: "workout-789",
            rpe: 6,
            muscleSoreness: ["core"],
            notes: "Felt good overall"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"notes\":\"Felt good overall\""))
        XCTAssertTrue(json.contains("\"muscle_soreness\""))
    }

    func testRPEFeedbackRequestUsesSnakeCaseKeys() throws {
        let request = RPEFeedbackRequest(
            workoutId: "w-1",
            rpe: 10,
            muscleSoreness: nil,
            notes: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        // Should use snake_case, not camelCase
        XCTAssertTrue(json.contains("\"workout_id\""))
        XCTAssertFalse(json.contains("\"workoutId\""))
        XCTAssertTrue(json.contains("\"muscle_soreness\"") || !json.contains("muscleSoreness"))
    }

    // MARK: - RPEFeedbackResponse Decoding Tests

    func testRPEFeedbackResponseDecoding() throws {
        let json = """
        {"success": true, "message": "Feedback recorded", "deload_recommended": true}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(RPEFeedbackResponse.self, from: data)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.message, "Feedback recorded")
        XCTAssertEqual(response.deloadRecommended, true)
    }

    func testRPEFeedbackResponseDecodingWithoutDeload() throws {
        let json = """
        {"success": true, "message": "OK"}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(RPEFeedbackResponse.self, from: data)

        XCTAssertTrue(response.success)
        XCTAssertNil(response.deloadRecommended)
    }

    func testRPEFeedbackResponseDecodingFalseDeload() throws {
        let json = """
        {"success": true, "message": "OK", "deload_recommended": false}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(RPEFeedbackResponse.self, from: data)

        XCTAssertFalse(response.deloadRecommended ?? true)
    }

    func testRPEFeedbackResponseDecodingFailure() throws {
        let json = """
        {"success": false, "message": "User not found"}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(RPEFeedbackResponse.self, from: data)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.message, "User not found")
    }
}
