//
//  XPBarViewTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for XP level calculations and XPBarView display logic.
//  AMA-1285
//

import XCTest
@testable import AmakaFlowCompanion

final class XPBarViewTests: XCTestCase {

    // MARK: - XPData Decoding

    func testXPDataDecoding() throws {
        let json = """
        {
            "xp_total": 1200,
            "current_level": 2,
            "level_name": "Regular",
            "xp_to_next_level": 300,
            "xp_today": 100,
            "daily_cap": 300
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try decoder.decode(XPData.self, from: json)

        XCTAssertEqual(data.xpTotal, 1200)
        XCTAssertEqual(data.currentLevel, 2)
        XCTAssertEqual(data.levelName, "Regular")
        XCTAssertEqual(data.xpToNextLevel, 300)
        XCTAssertEqual(data.xpToday, 100)
        XCTAssertEqual(data.dailyCap, 300)
    }

    func testXPDataDecodingMaxLevel() throws {
        let json = """
        {
            "xp_total": 80000,
            "current_level": 10,
            "level_name": "Legend",
            "xp_to_next_level": 0,
            "xp_today": 200,
            "daily_cap": 300
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try decoder.decode(XPData.self, from: json)

        XCTAssertEqual(data.currentLevel, 10)
        XCTAssertEqual(data.levelName, "Legend")
        XCTAssertEqual(data.xpToNextLevel, 0)
    }

    func testXPDataDecodingNewUser() throws {
        let json = """
        {
            "xp_total": 0,
            "current_level": 1,
            "level_name": "Newcomer",
            "xp_to_next_level": 500,
            "xp_today": 0,
            "daily_cap": 300
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try decoder.decode(XPData.self, from: json)

        XCTAssertEqual(data.xpTotal, 0)
        XCTAssertEqual(data.currentLevel, 1)
        XCTAssertEqual(data.levelName, "Newcomer")
        XCTAssertEqual(data.xpToNextLevel, 500)
    }
}
