//
//  StrengthAutoCaptureSettingsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2420 — experimental flag persistence + env override.
//

import XCTest
@testable import AmakaFlowCompanion

final class StrengthAutoCaptureSettingsTests: XCTestCase {
    private let key = StrengthAutoCaptureSettings.defaultsKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testDefaultIsOff() {
        XCTAssertFalse(StrengthAutoCaptureSettings.isEnabled)
    }

    func testTogglePersists() {
        StrengthAutoCaptureSettings.isEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        XCTAssertTrue(StrengthAutoCaptureSettings.isEnabled)

        StrengthAutoCaptureSettings.isEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
        XCTAssertFalse(StrengthAutoCaptureSettings.isEnabled)
    }
}
