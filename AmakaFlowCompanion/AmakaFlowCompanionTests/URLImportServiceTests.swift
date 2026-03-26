//
//  URLImportServiceTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for URLImportService response parsing and SharedContainerManager data types.
//  AMA-1257: iOS Share Extension — one-tap workout import from any app
//
//  NOTE: Types are declared inline because the test target links against
//  AmakaFlowCompanion, not the AmakaFlowShare extension target.
//

import XCTest

// MARK: - Inline copies of share extension types for testing

private struct TestShareIngestResponse: Codable {
    let title: String?
    let workoutType: String?
    let source: String?
    let needsClarification: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case workoutType = "workout_type"
        case source
        case needsClarification = "needs_clarification"
    }
}

private struct TestImportResult: Codable {
    let url: String
    let platform: String
    let title: String?
    let workoutType: String?
    let success: Bool
    let errorMessage: String?
    let timestamp: Date
}

final class URLImportServiceTests: XCTestCase {

    // MARK: - ShareIngestResponse Decoding

    func testDecodesSuccessfulResponse() throws {
        let json = """
        {
            "title": "Full Body HIIT Workout",
            "workout_type": "hiit",
            "source": "youtube",
            "needs_clarification": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TestShareIngestResponse.self, from: json)
        XCTAssertEqual(response.title, "Full Body HIIT Workout")
        XCTAssertEqual(response.workoutType, "hiit")
        XCTAssertEqual(response.source, "youtube")
        XCTAssertEqual(response.needsClarification, false)
    }

    func testDecodesResponseWithNulls() throws {
        let json = """
        {
            "title": null,
            "workout_type": null,
            "source": "instagram_reel",
            "needs_clarification": true
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TestShareIngestResponse.self, from: json)
        XCTAssertNil(response.title)
        XCTAssertNil(response.workoutType)
        XCTAssertEqual(response.source, "instagram_reel")
        XCTAssertEqual(response.needsClarification, true)
    }

    func testDecodesMinimalResponse() throws {
        let json = """
        {}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TestShareIngestResponse.self, from: json)
        XCTAssertNil(response.title)
        XCTAssertNil(response.workoutType)
        XCTAssertNil(response.source)
        XCTAssertNil(response.needsClarification)
    }

    // MARK: - ImportResult Round-trip

    func testImportResultRoundTrips() throws {
        let result = TestImportResult(
            url: "https://youtube.com/watch?v=abc",
            platform: "YouTube",
            title: "Test Workout",
            workoutType: "strength",
            success: true,
            errorMessage: nil,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(TestImportResult.self, from: data)

        XCTAssertEqual(decoded.url, result.url)
        XCTAssertEqual(decoded.platform, result.platform)
        XCTAssertEqual(decoded.title, result.title)
        XCTAssertEqual(decoded.workoutType, result.workoutType)
        XCTAssertEqual(decoded.success, true)
        XCTAssertNil(decoded.errorMessage)
    }

    func testErrorImportResultRoundTrips() throws {
        let result = TestImportResult(
            url: "https://tiktok.com/@user/video/123",
            platform: "TikTok",
            title: nil,
            workoutType: nil,
            success: false,
            errorMessage: "Server error (500): Internal server error",
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(TestImportResult.self, from: data)

        XCTAssertEqual(decoded.url, result.url)
        XCTAssertEqual(decoded.success, false)
        XCTAssertEqual(decoded.errorMessage, "Server error (500): Internal server error")
    }

    // MARK: - Snake Case Decoding

    func testSnakeCaseDecodingMatchesBackendFormat() throws {
        // Backend sends snake_case, we decode to camelCase
        let json = """
        {
            "title": "Push Day",
            "workout_type": "strength",
            "source": "tiktok",
            "needs_clarification": true
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TestShareIngestResponse.self, from: json)
        XCTAssertEqual(response.workoutType, "strength")
        XCTAssertEqual(response.needsClarification, true)
    }
}
