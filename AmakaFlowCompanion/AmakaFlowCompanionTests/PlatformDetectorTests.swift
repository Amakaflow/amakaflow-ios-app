//
//  PlatformDetectorTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for PlatformDetector — URL-to-platform detection and URL extraction.
//  AMA-1257: iOS Share Extension — one-tap workout import from any app
//
//  NOTE: These tests duplicate the PlatformDetector/SharedContainerManager types inline
//  because the test target links against AmakaFlowCompanion, not AmakaFlowShare.
//  The share extension is a separate target and cannot be @testable imported here.
//

import XCTest

// MARK: - Inline copies of share extension types for testing

private struct TestDetectedPlatform: Equatable {
    let name: String
    let iconSystemName: String
    let accentColorHex: String

    static let youtube = TestDetectedPlatform(name: "YouTube", iconSystemName: "play.rectangle.fill", accentColorHex: "#FF0000")
    static let instagram = TestDetectedPlatform(name: "Instagram", iconSystemName: "camera.fill", accentColorHex: "#E4405F")
    static let tiktok = TestDetectedPlatform(name: "TikTok", iconSystemName: "music.note", accentColorHex: "#000000")
    static let pinterest = TestDetectedPlatform(name: "Pinterest", iconSystemName: "pin.fill", accentColorHex: "#E60023")
    static let twitter = TestDetectedPlatform(name: "X / Twitter", iconSystemName: "at", accentColorHex: "#1DA1F2")
    static let facebook = TestDetectedPlatform(name: "Facebook", iconSystemName: "person.2.fill", accentColorHex: "#1877F2")
    static let reddit = TestDetectedPlatform(name: "Reddit", iconSystemName: "bubble.left.fill", accentColorHex: "#FF4500")
    static let safari = TestDetectedPlatform(name: "Web Link", iconSystemName: "safari.fill", accentColorHex: "#007AFF")
}

/// Mirror of PlatformDetector logic for testing
private enum TestPlatformDetector {
    static func detect(from urlString: String) -> TestDetectedPlatform {
        let lowered = urlString.lowercased()
        if lowered.contains("youtube.com") || lowered.contains("youtu.be") { return .youtube }
        if lowered.contains("instagram.com") || lowered.contains("instagr.am") { return .instagram }
        if lowered.contains("tiktok.com") { return .tiktok }
        if lowered.contains("pinterest.com") || lowered.contains("pin.it") { return .pinterest }
        if lowered.contains("twitter.com") || lowered.contains("x.com") || lowered.contains("t.co/") { return .twitter }
        if lowered.contains("facebook.com") || lowered.contains("fb.watch") || lowered.contains("fb.com") { return .facebook }
        if lowered.contains("reddit.com") || lowered.contains("redd.it") { return .reddit }
        return .safari
    }

    static func extractURLs(from text: String) -> [String] {
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.compactMap { match -> String? in
            guard let urlRange = Range(match.range, in: text) else { return nil }
            let urlString = String(text[urlRange])
            guard urlString.lowercased().hasPrefix("http") else { return nil }
            return urlString
        }
    }

    static func ingestSource(for platform: TestDetectedPlatform) -> String {
        switch platform {
        case .youtube: return "youtube"
        case .instagram: return "instagram_reel"
        case .tiktok: return "tiktok"
        case .pinterest: return "pinterest"
        default: return "url"
        }
    }
}

final class PlatformDetectorTests: XCTestCase {

    // MARK: - Platform Detection

    func testDetectsYouTubeFromStandardURL() {
        let result = TestPlatformDetector.detect(from: "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(result, .youtube)
    }

    func testDetectsYouTubeFromShortURL() {
        let result = TestPlatformDetector.detect(from: "https://youtu.be/abc123")
        XCTAssertEqual(result, .youtube)
    }

    func testDetectsYouTubeFromMobileURL() {
        let result = TestPlatformDetector.detect(from: "https://m.youtube.com/watch?v=abc123")
        XCTAssertEqual(result, .youtube)
    }

    func testDetectsInstagramFromReelURL() {
        let result = TestPlatformDetector.detect(from: "https://www.instagram.com/reel/abc123/")
        XCTAssertEqual(result, .instagram)
    }

    func testDetectsInstagramFromShortURL() {
        let result = TestPlatformDetector.detect(from: "https://instagr.am/p/abc123")
        XCTAssertEqual(result, .instagram)
    }

    func testDetectsTikTokFromStandardURL() {
        let result = TestPlatformDetector.detect(from: "https://www.tiktok.com/@user/video/123456")
        XCTAssertEqual(result, .tiktok)
    }

    func testDetectsTikTokFromVMShortURL() {
        let result = TestPlatformDetector.detect(from: "https://vm.tiktok.com/abc123/")
        XCTAssertEqual(result, .tiktok)
    }

    func testDetectsTikTokFromVTShortURL() {
        let result = TestPlatformDetector.detect(from: "https://vt.tiktok.com/abc123/")
        XCTAssertEqual(result, .tiktok)
    }

    func testDetectsPinterestFromStandardURL() {
        let result = TestPlatformDetector.detect(from: "https://www.pinterest.com/pin/123456/")
        XCTAssertEqual(result, .pinterest)
    }

    func testDetectsPinterestFromShortURL() {
        let result = TestPlatformDetector.detect(from: "https://pin.it/abc123")
        XCTAssertEqual(result, .pinterest)
    }

    func testDetectsTwitter() {
        let result = TestPlatformDetector.detect(from: "https://twitter.com/user/status/123")
        XCTAssertEqual(result, .twitter)
    }

    func testDetectsXDotCom() {
        let result = TestPlatformDetector.detect(from: "https://x.com/user/status/123")
        XCTAssertEqual(result, .twitter)
    }

    func testDetectsFacebook() {
        let result = TestPlatformDetector.detect(from: "https://www.facebook.com/watch/?v=123")
        XCTAssertEqual(result, .facebook)
    }

    func testDetectsFBWatch() {
        let result = TestPlatformDetector.detect(from: "https://fb.watch/abc123/")
        XCTAssertEqual(result, .facebook)
    }

    func testDetectsReddit() {
        let result = TestPlatformDetector.detect(from: "https://www.reddit.com/r/fitness/comments/abc123/")
        XCTAssertEqual(result, .reddit)
    }

    func testFallsBackToSafariForUnknownDomain() {
        let result = TestPlatformDetector.detect(from: "https://example.com/workout/plan")
        XCTAssertEqual(result, .safari)
    }

    func testHandlesCaseInsensitivity() {
        let result = TestPlatformDetector.detect(from: "HTTPS://WWW.YOUTUBE.COM/watch?v=abc")
        XCTAssertEqual(result, .youtube)
    }

    // MARK: - URL Extraction

    func testExtractsURLFromCleanString() {
        let urls = TestPlatformDetector.extractURLs(from: "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first, "https://www.youtube.com/watch?v=abc123")
    }

    func testExtractsURLFromInstagramShareText() {
        let text = "Check out this workout reel! https://www.instagram.com/reel/abc123/ #fitness #gym"
        let urls = TestPlatformDetector.extractURLs(from: text)
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.contains("instagram.com") == true)
    }

    func testExtractsMultipleURLs() {
        let text = """
        Here are two videos:
        https://www.youtube.com/watch?v=abc
        https://www.tiktok.com/@user/video/123
        """
        let urls = TestPlatformDetector.extractURLs(from: text)
        XCTAssertEqual(urls.count, 2)
    }

    func testReturnsEmptyForNoURLs() {
        let urls = TestPlatformDetector.extractURLs(from: "Just some text with no links at all")
        XCTAssertTrue(urls.isEmpty)
    }

    func testFiltersOutNonHTTPURLs() {
        let text = "Contact us at mailto:test@example.com or visit https://example.com"
        let urls = TestPlatformDetector.extractURLs(from: text)
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first?.hasPrefix("http") == true)
    }

    // MARK: - Ingest Source Mapping

    func testIngestSourceForYouTube() {
        XCTAssertEqual(TestPlatformDetector.ingestSource(for: .youtube), "youtube")
    }

    func testIngestSourceForInstagram() {
        XCTAssertEqual(TestPlatformDetector.ingestSource(for: .instagram), "instagram_reel")
    }

    func testIngestSourceForTikTok() {
        XCTAssertEqual(TestPlatformDetector.ingestSource(for: .tiktok), "tiktok")
    }

    func testIngestSourceForPinterest() {
        XCTAssertEqual(TestPlatformDetector.ingestSource(for: .pinterest), "pinterest")
    }

    func testIngestSourceForUnknownFallsBackToURL() {
        XCTAssertEqual(TestPlatformDetector.ingestSource(for: .safari), "url")
        XCTAssertEqual(TestPlatformDetector.ingestSource(for: .twitter), "url")
        XCTAssertEqual(TestPlatformDetector.ingestSource(for: .reddit), "url")
    }
}
