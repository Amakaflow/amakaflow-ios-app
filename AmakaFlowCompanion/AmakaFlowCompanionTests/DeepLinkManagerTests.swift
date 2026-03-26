//
//  DeepLinkManagerTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for DeepLinkManager URL parsing logic.
//  AMA-1259: Deep link import on iOS — Universal Links + custom scheme fallback
//

import XCTest
@testable import AmakaFlowCompanion

final class DeepLinkManagerTests: XCTestCase {

    var sut: DeepLinkManager!

    @MainActor
    override func setUp() {
        super.setUp()
        sut = DeepLinkManager.shared
        sut.clearPendingImport()
    }

    @MainActor
    override func tearDown() {
        sut.clearPendingImport()
        super.tearDown()
    }

    // MARK: - Universal Link Parsing

    @MainActor
    func testParsesUniversalLinkWithEncodedURL() {
        let url = URL(string: "https://amakaflow.com/import?url=https%3A%2F%2Fyoutu.be%2Fabc123")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .importURL("https://youtu.be/abc123"))
    }

    @MainActor
    func testParsesAppSubdomainUniversalLink() {
        let url = URL(string: "https://app.amakaflow.com/import?url=https%3A%2F%2Fwww.instagram.com%2Freel%2Fabc")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .importURL("https://www.instagram.com/reel/abc"))
    }

    @MainActor
    func testParsesFullYouTubeURL() {
        let encoded = "https://www.youtube.com/watch?v=dQw4w9WgXcQ".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://amakaflow.com/import?url=\(encoded)")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .importURL("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    // MARK: - Custom Scheme Parsing

    @MainActor
    func testParsesCustomSchemeImportURL() {
        let url = URL(string: "amakaflow://import?url=https%3A%2F%2Fyoutu.be%2Fabc123")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .importURL("https://youtu.be/abc123"))
    }

    @MainActor
    func testParsesCustomSchemeWithTikTokURL() {
        let tiktokURL = "https://www.tiktok.com/@user/video/123456"
        let encoded = tiktokURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "amakaflow://import?url=\(encoded)")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .importURL(tiktokURL))
    }

    // MARK: - Edge Cases

    @MainActor
    func testRejectsUnknownHost() {
        let url = URL(string: "https://example.com/import?url=https%3A%2F%2Fyoutu.be%2Fabc")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    @MainActor
    func testRejectsUnknownPath() {
        let url = URL(string: "https://amakaflow.com/workout?url=https%3A%2F%2Fyoutu.be%2Fabc")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    @MainActor
    func testRejectsMissingURLParam() {
        let url = URL(string: "https://amakaflow.com/import")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    @MainActor
    func testRejectsEmptyURLParam() {
        let url = URL(string: "https://amakaflow.com/import?url=")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    @MainActor
    func testRejectsNonHTTPURL() {
        let url = URL(string: "https://amakaflow.com/import?url=ftp%3A%2F%2Fexample.com%2Ffile")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    @MainActor
    func testRejectsUnknownCustomScheme() {
        let url = URL(string: "otherscheme://import?url=https%3A%2F%2Fyoutu.be%2Fabc")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    @MainActor
    func testRejectsCustomSchemeWithWrongHost() {
        let url = URL(string: "amakaflow://workout?url=https%3A%2F%2Fyoutu.be%2Fabc")!
        let action = sut.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    // MARK: - handleIncomingURL State Changes

    @MainActor
    func testHandleIncomingURLSetsPendingImport() {
        let url = URL(string: "https://amakaflow.com/import?url=https%3A%2F%2Fyoutu.be%2Fabc123")!
        let handled = sut.handleIncomingURL(url)
        XCTAssertTrue(handled)
        XCTAssertEqual(sut.pendingImportURL, "https://youtu.be/abc123")
        XCTAssertTrue(sut.showImportSheet)
    }

    @MainActor
    func testHandleIncomingURLReturnsFalseForUnknown() {
        let url = URL(string: "https://example.com/something")!
        let handled = sut.handleIncomingURL(url)
        XCTAssertFalse(handled)
        XCTAssertNil(sut.pendingImportURL)
        XCTAssertFalse(sut.showImportSheet)
    }

    @MainActor
    func testClearPendingImport() {
        let url = URL(string: "https://amakaflow.com/import?url=https%3A%2F%2Fyoutu.be%2Fabc123")!
        sut.handleIncomingURL(url)
        XCTAssertTrue(sut.showImportSheet)

        sut.clearPendingImport()
        XCTAssertNil(sut.pendingImportURL)
        XCTAssertFalse(sut.showImportSheet)
    }

    // MARK: - Platform Detection (via DeepLinkImportViewModel)

    @MainActor
    func testPlatformDetectionYouTube() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(platform, .youtube)
    }

    @MainActor
    func testPlatformDetectionYouTuBe() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://youtu.be/abc123")
        XCTAssertEqual(platform, .youtube)
    }

    @MainActor
    func testPlatformDetectionInstagram() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://www.instagram.com/reel/abc")
        XCTAssertEqual(platform, .instagram)
    }

    @MainActor
    func testPlatformDetectionTikTok() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://www.tiktok.com/@user/video/123")
        XCTAssertEqual(platform, .tiktok)
    }

    @MainActor
    func testPlatformDetectionPinterest() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://www.pinterest.com/pin/123")
        XCTAssertEqual(platform, .pinterest)
    }

    @MainActor
    func testPlatformDetectionTwitter() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://x.com/user/status/123")
        XCTAssertEqual(platform, .twitter)
    }

    @MainActor
    func testPlatformDetectionFacebook() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://fb.watch/abc123")
        XCTAssertEqual(platform, .facebook)
    }

    @MainActor
    func testPlatformDetectionReddit() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://www.reddit.com/r/fitness/post/123")
        XCTAssertEqual(platform, .reddit)
    }

    @MainActor
    func testPlatformDetectionGenericWeb() {
        let platform = DeepLinkImportViewModel.detectPlatform(from: "https://example.com/workout")
        XCTAssertEqual(platform, .web)
    }

    // MARK: - Ingest Source Mapping

    @MainActor
    func testIngestSourceYouTube() {
        XCTAssertEqual(DeepLinkPlatform.youtube.ingestSource, "youtube")
    }

    @MainActor
    func testIngestSourceInstagram() {
        XCTAssertEqual(DeepLinkPlatform.instagram.ingestSource, "instagram_reel")
    }

    @MainActor
    func testIngestSourceTikTok() {
        XCTAssertEqual(DeepLinkPlatform.tiktok.ingestSource, "tiktok")
    }

    @MainActor
    func testIngestSourcePinterest() {
        XCTAssertEqual(DeepLinkPlatform.pinterest.ingestSource, "pinterest")
    }

    @MainActor
    func testIngestSourceGenericURL() {
        XCTAssertEqual(DeepLinkPlatform.web.ingestSource, "url")
        XCTAssertEqual(DeepLinkPlatform.twitter.ingestSource, "url")
        XCTAssertEqual(DeepLinkPlatform.facebook.ingestSource, "url")
        XCTAssertEqual(DeepLinkPlatform.reddit.ingestSource, "url")
    }

    // MARK: - DeepLinkIngestResponse Decoding

    @MainActor
    func testDecodesIngestResponse() throws {
        let json = """
        {
            "title": "Full Body HIIT",
            "workout_type": "hiit",
            "source": "youtube",
            "needs_clarification": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(DeepLinkIngestResponse.self, from: json)
        XCTAssertEqual(response.title, "Full Body HIIT")
        XCTAssertEqual(response.workoutType, "hiit")
        XCTAssertEqual(response.source, "youtube")
        XCTAssertEqual(response.needsClarification, false)
    }

    @MainActor
    func testDecodesMinimalIngestResponse() throws {
        let json = "{}".data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(DeepLinkIngestResponse.self, from: json)
        XCTAssertNil(response.title)
        XCTAssertNil(response.workoutType)
        XCTAssertNil(response.source)
        XCTAssertNil(response.needsClarification)
    }
}
