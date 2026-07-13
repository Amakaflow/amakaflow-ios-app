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
          ]
        }
        """.data(using: .utf8)!
    }
}
