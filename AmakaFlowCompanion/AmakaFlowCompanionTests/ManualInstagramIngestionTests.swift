//
//  ManualInstagramIngestionTests.swift
//  AmakaFlowCompanionTests
//
//  Integration tests for manual Instagram ingestion using MockAPIService
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ManualInstagramIngestionTests: XCTestCase {

    var mockAPI: MockAPIService!

    override func setUp() async throws {
        mockAPI = MockAPIService()
    }

    override func tearDown() async throws {
        mockAPI = nil
    }

    // MARK: - MockAPIService ingestText Tracking

    func testMockAPIServiceTracksIngestTextCall() async throws {
        mockAPI.ingestTextResult = .success(
            IngestTextResponse(name: "Test Workout", sport: "strength", source: "instagram")
        )

        XCTAssertFalse(mockAPI.ingestTextCalled)
        _ = try await mockAPI.ingestText(text: "3x10 squats", source: "instagram")
        XCTAssertTrue(mockAPI.ingestTextCalled)
    }

    func testMockAPIServiceReturnsConfiguredSuccess() async throws {
        let expected = IngestTextResponse(name: "AMRAP 10", sport: "conditioning", source: "instagram")
        mockAPI.ingestTextResult = .success(expected)

        let response = try await mockAPI.ingestText(text: "AMRAP 10 min: burpees, box jumps", source: "instagram")
        XCTAssertEqual(response.name, "AMRAP 10")
        XCTAssertEqual(response.sport, "conditioning")
    }

    func testMockAPIServiceReturnsConfiguredError() async {
        mockAPI.ingestTextResult = .failure(APIError.serverError(500))

        do {
            _ = try await mockAPI.ingestText(text: "test", source: nil)
            XCTFail("Expected error to be thrown")
        } catch {
            guard case APIError.serverError(let code) = error else {
                XCTFail("Expected serverError, got \(error)")
                return
            }
            XCTAssertEqual(code, 500)
        }
    }

    func testMockAPIServiceThrowsNotImplementedWhenNoResult() async {
        // ingestTextResult is nil by default
        do {
            _ = try await mockAPI.ingestText(text: "test", source: nil)
            XCTFail("Expected notImplemented error")
        } catch {
            guard case APIError.notImplemented = error else {
                XCTFail("Expected notImplemented, got \(error)")
                return
            }
        }
    }

    // MARK: - Protocol Convenience Extension

    func testIngestTextConvenienceDefaultsSourceToNil() async throws {
        mockAPI.ingestTextResult = .success(
            IngestTextResponse(name: "Workout", sport: nil, source: nil)
        )

        // Call the convenience method (no source parameter)
        _ = try await mockAPI.ingestText(text: "test workout")
        XCTAssertTrue(mockAPI.ingestTextCalled)
    }

    // MARK: - FixtureAPIService

    #if DEBUG
    func testFixtureAPIServiceReturnsCannedResponse() async throws {
        let fixtureAPI = FixtureAPIService()

        let response = try await fixtureAPI.ingestText(text: "any text", source: "instagram")
        XCTAssertEqual(response.name, "Fixture Workout")
        XCTAssertEqual(response.sport, "strength")
        XCTAssertEqual(response.source, "instagram")
    }

    func testFixtureAPIServicePassesThroughSource() async throws {
        let fixtureAPI = FixtureAPIService()

        let response = try await fixtureAPI.ingestText(text: "any text", source: "https://instagram.com/p/abc")
        XCTAssertEqual(response.source, "https://instagram.com/p/abc")
    }
    #endif
}
