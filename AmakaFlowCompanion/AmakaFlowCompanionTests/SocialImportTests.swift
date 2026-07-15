//
//  SocialImportTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2285: social import happy path, provenance badges, failure mapping, draft decode.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class SocialImportTests: XCTestCase {

    private var mockAPI: MockAPIService!
    private var mockPairing: MockPairingService!
    private var sut: SocialImportViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI = await MockAPIService()
        mockPairing = await MockPairingService()
        mockPairing.isPaired = true
        mockPairing.userProfile = UserProfile(id: "user-1", email: "david@amakaflow.com", name: "David", avatarUrl: nil)
        let deps = await AppDependencies(
            apiService: mockAPI,
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        sut = SocialImportViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        sut = nil
        mockAPI = nil
        mockPairing = nil
        try await super.tearDown()
    }

    func testImportURLThenSaveToLibraryHappyPath() async throws {
        mockAPI.ingestSocialURLResult = .success(sampleIngestJSON())
        mockAPI.saveWorkoutResult = .success(
            Workout(
                id: "saved-1",
                name: "IG Push Day",
                sport: .strength,
                duration: 2400,
                intervals: [],
                source: .instagram,
                sourceUrl: "https://instagram.com/reel/abc"
            )
        )

        await sut.importURL("https://instagram.com/reel/abc", platformHint: .instagram)

        guard case .preview = sut.phase else {
            return XCTFail("Expected preview, got \(sut.phase)")
        }
        XCTAssertEqual(sut.draft?.title, "IG Push Day")
        XCTAssertEqual(sut.draft?.platform, .instagram)
        XCTAssertTrue(sut.canEdit)
        XCTAssertTrue(mockAPI.ingestSocialURLCalled)

        await sut.saveToLibrary()

        guard case .saved(let id) = sut.phase else {
            return XCTFail("Expected saved, got \(sut.phase)")
        }
        XCTAssertEqual(id, "saved-1")
        XCTAssertTrue(mockAPI.saveWorkoutCalled)
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.source, "instagram")
        XCTAssertEqual(mockAPI.lastSaveWorkoutRequest?.sourceUrl, "https://instagram.com/reel/abc")
    }

    func testProvenanceBadgesForSocialImportSources() {
        let cases: [(String, String)] = [
            ("manual", "Manual"),
            ("ai", "AI"),
            ("coach", "Coach"),
            ("youtube", "YouTube"),
            ("image", "Screenshot"),
            ("instagram", "Instagram"),
            ("tiktok", "TikTok")
        ]
        for (raw, label) in cases {
            XCTAssertEqual(
                WorkoutSourceProvenance.badge(for: raw)?.label,
                label,
                "source=\(raw)"
            )
        }
    }

    func testAuthFailureFailFastWithoutNetwork() async {
        mockPairing.isPaired = false

        await sut.importURL("https://tiktok.com/@x/video/1", platformHint: .tiktok)

        guard case .failed(let failure) = sut.phase else {
            return XCTFail("Expected failed, got \(sut.phase)")
        }
        guard case .auth = failure else {
            return XCTFail("Expected auth failure, got \(failure)")
        }
        XCTAssertFalse(mockAPI.ingestSocialURLCalled)
    }

    func testParseFailureMapsWithoutCrashing() async {
        mockAPI.ingestSocialURLResult = .failure(APIError.serverErrorWithBody(422, "{\"detail\":\"Could not parse\"}"))

        await sut.importURL("https://youtube.com/watch?v=bad")

        guard case .failed(let failure) = sut.phase else {
            return XCTFail("Expected failed, got \(sut.phase)")
        }
        guard case .parse = failure else {
            return XCTFail("Expected parse failure, got \(failure)")
        }
        XCTAssertFalse(failure.userMessage.isEmpty)
    }

    func testNetworkFailureMapsWithoutCrashing() async {
        mockAPI.ingestSocialTextResult = .failure(URLError(.timedOut))

        await sut.importPlainText("3x10 squats")

        guard case .failed(let failure) = sut.phase else {
            return XCTFail("Expected failed, got \(sut.phase)")
        }
        guard case .network = failure else {
            return XCTFail("Expected network failure, got \(failure)")
        }
    }

    func testSocialImportFailureMapCoversAPIErrorURLErrorCTAError() {
        XCTAssertEqual(
            SocialImportFailure.map(APIError.unauthorized).title,
            "Sign in required"
        )
        XCTAssertEqual(
            SocialImportFailure.map(URLError(.notConnectedToInternet)).title,
            "Network error"
        )
        XCTAssertEqual(
            SocialImportFailure.map(CTAError.decoding(description: "bad json")).title,
            "Couldn't parse workout"
        )
    }

    func testDraftDecodeFromIngestJSONWithBlocks() throws {
        let data = sampleIngestJSON()
        let draft = try SocialImportDraft.fromIngestJSON(
            data,
            platform: .tiktok,
            sourceURL: "https://tiktok.com/@x/video/1",
            equipmentEmpty: true,
            equipmentNote: "No equipment profile yet"
        )
        XCTAssertEqual(draft.title, "IG Push Day")
        XCTAssertEqual(draft.exercises.count, 2)
        XCTAssertEqual(draft.exercises[0].name, "Bench Press")
        XCTAssertEqual(draft.platform, .tiktok)
        XCTAssertTrue(draft.equipmentEmpty)
    }

    func testDraftDecodeThinPayloadStillEditable() throws {
        let json = """
        {"title":"Thin Import","source":"https://youtube.com/watch?v=1"}
        """.data(using: .utf8)!
        let draft = try SocialImportDraft.fromIngestJSON(
            json,
            platform: .youtube,
            sourceURL: nil,
            equipmentEmpty: false,
            equipmentNote: nil
        )
        XCTAssertEqual(draft.title, "Thin Import")
        XCTAssertFalse(draft.exercises.isEmpty)
        XCTAssertEqual(draft.toWorkoutSaveRequest().source, "youtube")
    }

    func testNormalizeReelsURLToReel() {
        let plural = "https://www.instagram.com/reels/DMqEsenN6Dl/"
        let normalized = SocialImportPlatform.normalizeForIngest(plural)
        XCTAssertEqual(normalized, "https://www.instagram.com/reel/DMqEsenN6Dl/")
        XCTAssertEqual(
            SocialImportPlatform.normalizeForIngest("https://www.instagram.com/reel/DMqEsenN6Dl/"),
            "https://www.instagram.com/reel/DMqEsenN6Dl/"
        )
        XCTAssertTrue(SocialImportPlatform.isWorkoutImportURL(plural))
        XCTAssertFalse(SocialImportPlatform.isWorkoutImportURL("https://www.nytimes.com/article"))
    }

    func testLibraryPasteRouterRoutesSocialToImport() {
        let social = LibraryPasteRouter.destination(
            clipboardString: "https://www.instagram.com/reels/DMqEsenN6Dl/"
        )
        guard case .socialImport(let url, let platform) = social else {
            return XCTFail("Expected socialImport, got \(social)")
        }
        XCTAssertEqual(platform, .instagram)
        XCTAssertEqual(url, "https://www.instagram.com/reel/DMqEsenN6Dl/")

        let article = LibraryPasteRouter.destination(
            clipboardString: "https://www.trainingpeaks.com/plan/123"
        )
        guard case .knowledge = article else {
            return XCTFail("Expected knowledge for non-social URL, got \(article)")
        }

        let empty = LibraryPasteRouter.destination(clipboardString: nil)
        guard case .knowledge = empty else {
            return XCTFail("Expected knowledge for empty clipboard, got \(empty)")
        }
    }

    func testDraftDecodeMapsProvenanceFromIngestJSON() throws {
        let json = """
        {
          "title": "HYROX Upper Body",
          "sport": "strength",
          "blocks": [
            {
              "exercises": [
                {"name": "Push-Ups", "sets": 3, "reps": 15},
                {"name": "Bench Press", "sets": 4, "reps": 8},
                {"name": "Pull-Ups", "sets": 3, "reps": 10}
              ]
            }
          ],
          "_provenance": {
            "mode": "instagram_reel",
            "creator": "trainwithsmee",
            "shortcode": "DMqEsenN6Dl",
            "caption_snippet": "HYROX upper body session — push + pull",
            "transcript_snippet": "first up push-ups then bench",
            "source_url": "https://www.instagram.com/reel/DMqEsenN6Dl/"
          }
        }
        """.data(using: .utf8)!
        let draft = try SocialImportDraft.fromIngestJSON(
            json,
            platform: .instagram,
            sourceURL: "https://www.instagram.com/reels/DMqEsenN6Dl/",
            equipmentEmpty: false,
            equipmentNote: nil
        )
        XCTAssertEqual(draft.postProvenance?.creatorDisplay, "@trainwithsmee")
        XCTAssertEqual(draft.postProvenance?.shortcode, "DMqEsenN6Dl")
        XCTAssertTrue(draft.postProvenance?.contentSnippet?.contains("HYROX") == true)
        XCTAssertEqual(draft.exercises.count, 3)
        XCTAssertEqual(draft.exercises[0].name, "Push-Ups")
    }

    func testTier403MapsToHonestTierFailure() {
        let body = "{\"detail\":\"Instagram auto-extraction requires a Pro or Trainer subscription.\"}"
        let failure = SocialImportFailure.map(APIError.serverErrorWithBody(403, body))
        guard case .tier(let message) = failure else {
            return XCTFail("Expected tier failure, got \(failure)")
        }
        XCTAssertEqual(failure.title, "Pro required")
        XCTAssertTrue(message.lowercased().contains("pro"))
    }

    func testImportURLNormalizesReelsBeforeIngest() async {
        mockAPI.ingestSocialURLResult = .success(sampleIngestJSON())

        await sut.importURL("https://www.instagram.com/reels/DMqEsenN6Dl/", platformHint: .instagram)

        XCTAssertEqual(mockAPI.lastIngestSocialURL, "https://www.instagram.com/reel/DMqEsenN6Dl/")
        guard case .preview = sut.phase else {
            return XCTFail("Expected preview, got \(sut.phase)")
        }
    }

    private func sampleIngestJSON() -> Data {
        """
        {
          "title": "IG Push Day",
          "sport": "strength",
          "blocks": [
            {
              "exercises": [
                {"name": "Bench Press", "sets": 4, "reps": 8},
                {"name": "Overhead Press", "sets": 3, "reps": 10}
              ]
            }
          ],
          "_provenance": {
            "creator": "fitcoach",
            "caption_snippet": "Push day — bench and OHP",
            "shortcode": "abc"
          }
        }
        """.data(using: .utf8)!
    }
}
