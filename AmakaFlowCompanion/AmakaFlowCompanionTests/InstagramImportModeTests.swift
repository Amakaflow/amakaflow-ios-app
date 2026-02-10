//
//  InstagramImportModeTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for InstagramImportMode enum and IngestTextResponse decoding
//

import XCTest
@testable import AmakaFlowCompanion

final class InstagramImportModeTests: XCTestCase {

    // MARK: - InstagramImportMode Enum

    func testInstagramImportModeRawValues() {
        XCTAssertEqual(InstagramImportMode.automatic.rawValue, "automatic")
        XCTAssertEqual(InstagramImportMode.manual.rawValue, "manual")
    }

    func testInstagramImportModeInitFromRawValue() {
        // Ensures @AppStorage round-trip works
        XCTAssertEqual(InstagramImportMode(rawValue: "automatic"), .automatic)
        XCTAssertEqual(InstagramImportMode(rawValue: "manual"), .manual)
        XCTAssertNil(InstagramImportMode(rawValue: "unknown"))
    }

    func testInstagramImportModeTitles() {
        XCTAssertEqual(InstagramImportMode.automatic.title, "Automatic")
        XCTAssertEqual(InstagramImportMode.manual.title, "Manual")
    }

    func testInstagramImportModeSubtitles() {
        XCTAssertTrue(InstagramImportMode.automatic.subtitle.contains("Apify"))
        XCTAssertTrue(InstagramImportMode.manual.subtitle.contains("caption"))
    }

    func testInstagramImportModeAllCases() {
        XCTAssertEqual(InstagramImportMode.allCases.count, 2)
        XCTAssertTrue(InstagramImportMode.allCases.contains(.automatic))
        XCTAssertTrue(InstagramImportMode.allCases.contains(.manual))
    }

    // MARK: - IngestTextResponse Decoding

    func testIngestTextResponseDecodesFullPayload() throws {
        let json = """
        {"name": "AMRAP 10 min", "sport": "strength", "source": "instagram"}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(IngestTextResponse.self, from: json)

        XCTAssertEqual(response.name, "AMRAP 10 min")
        XCTAssertEqual(response.sport, "strength")
        XCTAssertEqual(response.source, "instagram")
    }

    func testIngestTextResponseDecodesPartialPayload() throws {
        let json = """
        {"name": null, "sport": null, "source": null}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(IngestTextResponse.self, from: json)

        XCTAssertNil(response.name)
        XCTAssertNil(response.sport)
        XCTAssertNil(response.source)
    }

    func testIngestTextResponseIgnoresExtraFields() throws {
        // Backend returns a full Workout JSON; our struct should decode fine
        let json = """
        {
            "name": "Full Body Workout",
            "sport": "strength",
            "source": "instagram",
            "id": "wk_12345",
            "duration": 3600,
            "intervals": [],
            "description": "A great workout"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(IngestTextResponse.self, from: json)

        XCTAssertEqual(response.name, "Full Body Workout")
        XCTAssertEqual(response.sport, "strength")
        XCTAssertEqual(response.source, "instagram")
    }

    func testIngestTextResponseDecodesEmptyObject() throws {
        let json = "{}".data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(IngestTextResponse.self, from: json)

        XCTAssertNil(response.name)
        XCTAssertNil(response.sport)
        XCTAssertNil(response.source)
    }
}
