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

        let tiktok = LibraryPasteRouter.destination(
            clipboardString: "https://www.tiktok.com/@coach/video/123"
        )
        guard case .socialImport(_, let ttPlatform) = tiktok else {
            return XCTFail("Expected socialImport for TikTok, got \(tiktok)")
        }
        XCTAssertEqual(ttPlatform, .tiktok)

        let youtube = LibraryPasteRouter.destination(
            clipboardString: "https://www.youtube.com/watch?v=abc123"
        )
        guard case .socialImport(_, let ytPlatform) = youtube else {
            return XCTFail("Expected socialImport for YouTube, got \(youtube)")
        }
        XCTAssertEqual(ytPlatform, .youtube)

        let lookalike = LibraryPasteRouter.destination(
            clipboardString: "https://instagram.com.evil/phishing"
        )
        guard case .knowledge = lookalike else {
            return XCTFail("Expected knowledge for lookalike host, got \(lookalike)")
        }

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

    func testBare403WithoutBodyMustNotMasqueradeAsSessionExpired() {
        let failure = SocialImportFailure.map(APIError.serverError(403))
        guard case .parse(let message) = failure else {
            return XCTFail("Expected parse for body-less 403, got \(failure)")
        }
        XCTAssertFalse(message.lowercased().contains("session expired"))
        XCTAssertTrue(message.lowercased().contains("forbidden"))
    }

    func testPrivateProfile403MapsToParseNotTier() {
        let body = "{\"detail\":\"This profile is private\"}"
        let failure = SocialImportFailure.map(APIError.serverErrorWithBody(403, body))
        guard case .parse(let message) = failure else {
            return XCTFail("Expected parse (not tier) for private profile 403, got \(failure)")
        }
        XCTAssertTrue(message.lowercased().contains("private"))
    }

    func testImportURLNormalizesReelsBeforeIngest() async {
        mockAPI.ingestSocialURLResult = .success(sampleIngestJSON())

        await sut.importURL("https://www.instagram.com/reels/DMqEsenN6Dl/", platformHint: .instagram)

        XCTAssertEqual(mockAPI.lastIngestSocialURL, "https://www.instagram.com/reel/DMqEsenN6Dl/")
        guard case .preview = sut.phase else {
            return XCTFail("Expected preview, got \(sut.phase)")
        }
    }

    func testSaveRejectsPlaceholderOnlyExercises() async {
        sut.loadDraft(
            SocialImportDraft(
                title: "Thin",
                sport: "strength",
                platform: .instagram,
                sourceURL: "https://www.instagram.com/reel/x/",
                exercises: [SocialImportExercise(name: "Add exercises", sets: 3, reps: 10)],
                equipmentNote: nil,
                equipmentEmpty: false,
                postProvenance: nil
            )
        )

        await sut.saveToLibrary()

        guard case .failed(let failure) = sut.phase else {
            return XCTFail("Expected failed, got \(sut.phase)")
        }
        guard case .parse = failure else {
            return XCTFail("Expected parse failure, got \(failure)")
        }
        XCTAssertFalse(mockAPI.saveWorkoutCalled)
    }

    func testMapperSaveBodyUsesWorkoutDataBlocksShape() throws {
        let request = WorkoutSaveRequest(
            name: "Upper Body Strength Day",
            sport: "strength",
            intervals: [
                WorkoutSaveInterval(type: "reps", name: "Dumbbell Bench Press", sets: 5, reps: 5),
                WorkoutSaveInterval(type: "reps", name: "Sled Pull", sets: 12, reps: 12)
            ],
            source: WorkoutSource.instagram.rawValue,
            sourceUrl: "https://www.instagram.com/reel/DX9abc/"
        )

        let body = try APIService.mapperSaveBody(from: request, source: WorkoutSource.instagram.rawValue)
        XCTAssertNotNil(body["workout_data"])
        XCTAssertEqual(body["device"] as? String, "ios")
        XCTAssertEqual(body["sources"] as? [String], ["instagram"])

        let workoutData = body["workout_data"] as? [String: Any]
        let blocks = workoutData?["blocks"] as? [[String: Any]]
        let exercises = blocks?.first?["exercises"] as? [[String: Any]]
        XCTAssertEqual(exercises?.count, 2)
        XCTAssertEqual(exercises?.first?["name"] as? String, "Dumbbell Bench Press")
        XCTAssertEqual(exercises?.first?["sets"] as? Int, 5)
        XCTAssertEqual(exercises?.first?["reps"] as? Int, 5)

        let metadata = workoutData?["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["source_url"] as? String, "https://www.instagram.com/reel/DX9abc/")
    }

    func testMapperSaveBodyRejectsEmptyExerciseList() {
        let request = WorkoutSaveRequest(
            name: "Empty",
            sport: "strength",
            intervals: [WorkoutSaveInterval(type: "rest", seconds: 60)],
            source: WorkoutSource.instagram.rawValue
        )

        XCTAssertThrowsError(try APIService.mapperSaveBody(from: request, source: "instagram")) { error in
            guard case APIError.serverErrorWithBody(422, let message) = error else {
                return XCTFail("Expected 422 body error, got \(error)")
            }
            XCTAssertTrue(message.lowercased().contains("exercise"))
        }
    }

    func testSocialImportFailureFormatsFastAPIValidationDetail() {
        let body = """
        {"detail":[{"type":"missing","loc":["body","workout_data"],"msg":"Field required","input":{}}]}
        """
        let failure = SocialImportFailure.map(APIError.serverErrorWithBody(422, body))
        guard case .parse(let message) = failure else {
            return XCTFail("Expected parse failure, got \(failure)")
        }
        XCTAssertEqual(message, "workout_data: Field required")
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

// MARK: - APIService contract (AMA-2297 save → Library visibility)

@MainActor
final class APIServiceSocialImportContractTests: XCTestCase {
    private var api: APIService!
    private var savedIsPaired: Bool!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        api = APIService(session: MockURLProtocol.mockSession())
        savedIsPaired = PairingService.shared.isPaired
        PairingService.shared.isPaired = true
    }

    override func tearDown() {
        PairingService.shared.isPaired = savedIsPaired
        api = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testIngestSocialURLUsesExtendedTimeoutForReelFetch() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.timeoutInterval, 120, accuracy: 0.001)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = """
            {"title":"Hyrox","sport":"strength","blocks":[{"exercises":[{"name":"Sled Push","sets":4,"reps":1}]}]}
            """.data(using: .utf8)!
            return (response, data)
        }

        _ = try await api.ingestSocialURL(
            url: "https://www.instagram.com/reel/DMYIJsTMVMC/",
            platform: .instagram
        )

        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 1)
        XCTAssertTrue(
            MockURLProtocol.interceptedRequests[0].url?.path.contains("instagram_reel") == true
        )
    }

    func testSaveWorkoutWithProvenancePushesToIOSCompanionForLibrary() async throws {
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            if path.hasSuffix("/workouts/save") {
                let data = """
                {"success":true,"workout_id":"wk-social-1","message":"Workout saved successfully","is_update":false}
                """.data(using: .utf8)!
                return (response, data)
            }

            if path.contains("/push/ios-companion") {
                XCTAssertEqual(request.httpMethod, "POST")
                let data = """
                {"success":true,"iosCompanionWorkoutId":"wk-social-1","status":"queued"}
                """.data(using: .utf8)!
                return (response, data)
            }

            XCTFail("Unexpected path: \(path)")
            return (response, Data())
        }

        let request = WorkoutSaveRequest(
            name: "Hyrox Import",
            sport: "strength",
            intervals: [WorkoutSaveInterval(type: "reps", name: "Sled Push", sets: 4, reps: 1)],
            source: WorkoutSource.instagram.rawValue,
            sourceUrl: "https://www.instagram.com/reel/DMYIJsTMVMC/"
        )

        let workout = try await api.saveWorkout(request)

        XCTAssertEqual(workout.id, "wk-social-1")
        XCTAssertEqual(MockURLProtocol.interceptedRequests.count, 2)
        XCTAssertTrue(
            MockURLProtocol.interceptedRequests[0].url?.path.hasSuffix("/workouts/save") == true
        )
        XCTAssertTrue(
            MockURLProtocol.interceptedRequests[1].url?.path.contains("/push/ios-companion") == true
        )
    }
}
