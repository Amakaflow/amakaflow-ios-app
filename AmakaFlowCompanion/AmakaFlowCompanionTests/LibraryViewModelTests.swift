//
//  LibraryViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2004: Library tab list, filters, empty/error coverage.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class LibraryViewModelTests: XCTestCase {
    private var api: MockAPIService!
    private var viewModel: LibraryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
        viewModel = LibraryViewModel(apiService: api)
    }

    override func tearDown() async throws {
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testInitialStateIsLoading() {
        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.ctaError)
        XCTAssertEqual(viewModel.savedSubtitle, "Loading saved ideas")
    }

    func testLoadSuccessSurfacesItemsAndTags() async {
        let response = Components.Schemas.LibraryItemList(
            items: [
                item(id: "strength", kind: .workout, tags: ["strength", "beginner"]),
                item(id: "video", kind: .video, tags: ["mobility"])
            ],
            total: 2
        )
        api.listLibraryItemsResult = .success(response)

        await viewModel.load()

        XCTAssertTrue(api.listLibraryItemsCalled)
        XCTAssertNil(api.lastListLibraryItemsKind, "LibraryViewModel should fetch all items for multi-kind client filtering")
        XCTAssertNil(api.lastListLibraryItemsTag)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.items, response.items)
        XCTAssertEqual(viewModel.availableTags, ["beginner", "mobility", "strength"])
        XCTAssertEqual(viewModel.savedSubtitle, "2 saved items")
        XCTAssertNil(viewModel.ctaError)
    }

    func testLoadEmptyShowsHonestEmptyState() async {
        api.listLibraryItemsResult = .success(Components.Schemas.LibraryItemList(items: [], total: 0))

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.savedSubtitle, "0 saved items")
        XCTAssertEqual(LibraryCopy.emptyTitle, "Save workouts and ideas as you find them")
        XCTAssertEqual(LibraryCopy.pasteLink, "Paste a link")
    }

    func testKindFilterIsMultiSelectAndClientSide() async {
        api.listLibraryItemsResult = .success(
            Components.Schemas.LibraryItemList(
                items: [
                    item(id: "workout", kind: .workout),
                    item(id: "video", kind: .video),
                    item(id: "article", kind: .article),
                    item(id: "plan", kind: .plan)
                ],
                total: 4
            )
        )

        await viewModel.load()
        viewModel.toggleKind(.workout)
        viewModel.toggleKind(.video)

        XCTAssertNil(api.lastListLibraryItemsKind)
        XCTAssertEqual(Set(viewModel.items.map(\.kind)), [.workout, .video])
        XCTAssertEqual(viewModel.items.map(\.id), ["workout", "video"])
        XCTAssertTrue(viewModel.isKindSelected(.workout))
        XCTAssertTrue(viewModel.isKindSelected(.video))

        viewModel.clearKindFilters()
        XCTAssertEqual(viewModel.items.count, 4)
        XCTAssertTrue(viewModel.selectedKinds.isEmpty)
    }

    func testTagFilterIsSingleSelectAndCanClear() async {
        api.listLibraryItemsResult = .success(
            Components.Schemas.LibraryItemList(
                items: [
                    item(id: "strength-a", kind: .workout, tags: ["strength"]),
                    item(id: "strength-b", kind: .plan, tags: [" Strength ", "hyrox"]),
                    item(id: "mobility", kind: .video, tags: ["mobility"])
                ],
                total: 3
            )
        )

        await viewModel.load()
        viewModel.selectTag("strength")

        XCTAssertNil(api.lastListLibraryItemsTag)
        XCTAssertEqual(viewModel.items.map(\.id), ["strength-a", "strength-b"])
        XCTAssertEqual(viewModel.selectedTag, "strength")
        XCTAssertTrue(viewModel.isTagSelected("strength"))

        viewModel.selectTag("strength")
        XCTAssertNil(viewModel.selectedTag)
        XCTAssertEqual(viewModel.items.count, 3)
    }

    func testCombinedFiltersCanProduceEmptyStateWithoutZeroedGrid() async {
        api.listLibraryItemsResult = .success(
            Components.Schemas.LibraryItemList(
                items: [item(id: "article", kind: .article, tags: ["endurance"])],
                total: 1
            )
        )

        await viewModel.load()
        viewModel.toggleKind(.video)

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertTrue(viewModel.hasActiveFilters)

        viewModel.clearFilters()
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.items.map(\.id), ["article"])
    }

    func testLoadErrorMatrixMapsToCTAErrorAndRetry() async {
        let cases: [(Error, (CTAError) -> Bool, String)] = [
            (URLError(.notConnectedToInternet), { if case .network(let code, _) = $0 { return code == .notConnectedToInternet }; return false }, "network"),
            (APIError.serverErrorWithBody(503, "{\"detail\":\"Library unavailable\"}"), { if case .http(let status, let body, _) = $0 { return status == 503 && (body?.contains("Library unavailable") == true) }; return false }, "http"),
            (APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad library shape"))), { if case .decoding = $0 { return true }; return false }, "decoding")
        ]

        for (error, matcher, label) in cases {
            api = MockAPIService()
            api.listLibraryItemsResult = .failure(error)
            viewModel = LibraryViewModel(apiService: api)

            await viewModel.load()

            guard case .error(let ctaError) = viewModel.state else {
                XCTFail("Expected error state for \(label), got \(viewModel.state)")
                continue
            }
            XCTAssertTrue(matcher(ctaError), "Wrong CTAError mapping for \(label): \(ctaError)")
            XCTAssertEqual(viewModel.ctaError, ctaError)
            XCTAssertEqual(viewModel.lastFailedAction, .load)
            XCTAssertEqual(viewModel.savedSubtitle, "Unable to load")

            api.listLibraryItemsResult = .success(Components.Schemas.LibraryItemList(items: [item(id: "retry-ok")], total: 1))
            await viewModel.retryLastAction()
            XCTAssertEqual(viewModel.state, .content)
            XCTAssertEqual(viewModel.items.map(\.id), ["retry-ok"])
            XCTAssertNil(viewModel.ctaError)
        }
    }

    func testLoadRefreshFailurePreservesExistingItemsAndUsesToast() async {
        // Initial successful load
        api.listLibraryItemsResult = .success(Components.Schemas.LibraryItemList(
            items: [item(id: "item-1"), item(id: "item-2")],
            total: 2
        ))
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.items.count, 2)

        // Refresh fails
        api.listLibraryItemsResult = .failure(URLError(.notConnectedToInternet))
        await viewModel.load()

        // Content preserved; toast error shown instead of full-screen error
        XCTAssertEqual(viewModel.state, .content, "Refresh failure must not replace content with full-screen error")
        XCTAssertEqual(viewModel.items.count, 2, "Existing items must be preserved on refresh failure")
        XCTAssertNotNil(viewModel.ctaError, "Toast error must be shown on refresh failure")
        XCTAssertEqual(viewModel.lastFailedAction, .load)
    }

    func testDismissLoadErrorKeepsErrorStateInsteadOfFakeEmptyLibrary() async {
        api.listLibraryItemsResult = .failure(URLError(.notConnectedToInternet))

        await viewModel.load()
        viewModel.dismissError()

        XCTAssertNil(viewModel.ctaError)
        guard case .error = viewModel.state else {
            return XCTFail("Dismissed load error must remain in error state, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testDisplayKindLabelsAndIcons() {
        XCTAssertEqual(LibraryViewModel.displayKinds, [.workout, .video, .article, .plan])
        XCTAssertEqual(LibraryViewModel.kindLabel(.workout), "Workouts")
        XCTAssertEqual(LibraryViewModel.kindSingularLabel(.video), "Video")
        XCTAssertEqual(LibraryViewModel.kindIcon(.article), "doc.text.fill")
    }

    func testGeneratedDecoderHandlesLibrarySchemas() throws {
        let json = """
        {
          "items": [
            {
              "id": "lib-1",
              "title": "Saved strength idea",
              "kind": "workout",
              "sourceUrl": "https://example.com/workout",
              "sourceDomain": "example.com",
              "thumbnailUrl": null,
              "tags": ["strength", "saved"],
              "bookmarked": false,
              "savedAt": "2026-05-29T12:00:00Z"
            }
          ],
          "total": 1
        }
        """.data(using: .utf8)!

        let decoded = try APIService.makeGeneratedDecoder().decode(Components.Schemas.LibraryItemList.self, from: json)

        XCTAssertEqual(decoded.total, 1)
        XCTAssertEqual(decoded.items?.first?.id, "lib-1")
        XCTAssertEqual(decoded.items?.first?.kind, .workout)
        XCTAssertEqual(decoded.items?.first?.thumbnailUrl, nil)
        XCTAssertEqual(decoded.items?.first?.bookmarked, false)
    }

    func testFixtureServiceSurfacesItemsAcrossKindsAndSupportsEmptyKnob() async throws {
        let fixture = FixtureAPIService()

        let response = try await fixture.listLibraryItems(kind: nil, tag: nil)

        XCTAssertEqual(Set(response.items?.map(\.kind) ?? []), [.workout, .video, .article, .plan])
        XCTAssertTrue(response.items?.allSatisfy { $0.thumbnailUrl == nil && $0.bookmarked == false } == true)

        fixture.libraryItemsEmpty = true
        let empty = try await fixture.listLibraryItems(kind: nil, tag: nil)
        XCTAssertTrue(empty.items?.isEmpty == true)
    }

    // MARK: - AMA-2298 delete

    func testDeleteKnowledgeEntryRemovesFromListOptimistically() async {
        let knowledge = item(id: "article-1", kind: .article, title: "Zone two")
        api.listLibraryItemsResult = .success(Components.Schemas.LibraryItemList(items: [knowledge], total: 1))
        api.fetchWorkoutsResult = .success([])

        await viewModel.load()
        XCTAssertEqual(viewModel.entries.count, 1)

        let deleted = await viewModel.deleteEntry(.knowledge(knowledge))

        XCTAssertTrue(deleted)
        XCTAssertTrue(api.deleteKnowledgeCardCalled)
        XCTAssertEqual(api.lastDeletedKnowledgeCardID, "article-1")
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertNil(viewModel.ctaError)
    }

    func testDeleteWorkoutEntryRemovesFromListOptimistically() async {
        let workout = makeWorkout(id: "wo-1", name: "HIIT Follow-Along")
        api.listLibraryItemsResult = .success(Components.Schemas.LibraryItemList(items: [], total: 0))
        api.fetchWorkoutsResult = .success([workout])

        await viewModel.load()
        XCTAssertEqual(viewModel.entries.count, 1)

        let deleted = await viewModel.deleteEntry(.workout(workout))

        XCTAssertTrue(deleted)
        XCTAssertTrue(api.deleteWorkoutCalled)
        XCTAssertEqual(api.lastDeletedWorkoutID, "wo-1")
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(viewModel.entries.isEmpty)
    }

    func testDeleteFailureRestoresEntryAndSurfacesToast() async {
        let knowledge = item(id: "article-1", kind: .article, title: "Zone two")
        api.listLibraryItemsResult = .success(Components.Schemas.LibraryItemList(items: [knowledge], total: 1))
        api.fetchWorkoutsResult = .success([])
        api.deleteKnowledgeCardResult = .failure(URLError(.notConnectedToInternet))

        await viewModel.load()
        let deleted = await viewModel.deleteEntry(.knowledge(knowledge))

        XCTAssertFalse(deleted)
        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertNotNil(viewModel.ctaError)
        XCTAssertEqual(viewModel.lastFailedAction, .delete(.knowledge(knowledge)))
        XCTAssertEqual(viewModel.errorToastTitle, "Couldn't delete Library item")
        XCTAssertTrue(viewModel.ctaError?.isRetryable == true)

        api.deleteKnowledgeCardResult = .success(())
        await viewModel.retryLastAction()
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.ctaError)
    }

    func testDeleteLastItemShowsEmptyState() async {
        let workout = makeWorkout(id: "only", name: "Solo")
        api.listLibraryItemsResult = .success(Components.Schemas.LibraryItemList(items: [], total: 0))
        api.fetchWorkoutsResult = .success([workout])

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .content)

        _ = await viewModel.deleteEntry(.workout(workout))
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.savedSubtitle, "0 saved items")
    }

    func testFixtureDeleteMutatesLibraryAndWorkoutsWithoutRelaunch() async throws {
        let fixture = FixtureAPIService()
        let beforeLibrary = try await fixture.listLibraryItems(kind: nil, tag: nil)
        let articleID = "fixture-zone-two-article"
        XCTAssertTrue(beforeLibrary.items?.contains(where: { $0.id == articleID }) == true)

        try await fixture.deleteKnowledgeCard(id: articleID)
        let afterLibrary = try await fixture.listLibraryItems(kind: nil, tag: nil)
        XCTAssertFalse(afterLibrary.items?.contains(where: { $0.id == articleID }) == true)

        let beforeWorkouts = try await fixture.fetchWorkouts(isRetry: false)
        let workoutID = try XCTUnwrap(beforeWorkouts.first?.id)
        try await fixture.deleteWorkout(id: workoutID)
        let afterWorkouts = try await fixture.fetchWorkouts(isRetry: false)
        XCTAssertFalse(afterWorkouts.contains(where: { $0.id == workoutID }))
    }

    func testAddToLibraryURLNormalizationAndHTMLPreviewParsing() throws {
        let normalized = try XCTUnwrap(AddToLibraryViewModel.normalizedURL(from: " example.com/workout "))
        XCTAssertEqual(normalized.absoluteString, "https://example.com/workout")
        XCTAssertNil(AddToLibraryViewModel.normalizedURL(from: "ftp://example.com/file"))

        let html = """
        <html><head>
          <meta property="og:title" content="Strength &amp; Mobility">
          <meta content="https://cdn.example.com/card.png" property="og:image">
          <meta property="og:site_name" content="Coach Notes">
        </head></html>
        """
        let preview = AddToLibraryHTMLParser.preview(from: html, baseURL: normalized)

        XCTAssertEqual(preview.title, "Strength & Mobility")
        XCTAssertEqual(preview.imageURL?.absoluteString, "https://cdn.example.com/card.png")
        XCTAssertEqual(preview.siteName, "Coach Notes")
    }

    func testAddToLibraryKindAutoDetectsFromURLHost() throws {
        XCTAssertEqual(
            AddToLibraryViewModel.autoDetectKind(for: try XCTUnwrap(URL(string: "https://youtu.be/abc"))),
            .video
        )
        XCTAssertEqual(
            AddToLibraryViewModel.autoDetectKind(for: try XCTUnwrap(URL(string: "https://trainingpeaks.com/plan/123"))),
            .plan
        )
        XCTAssertEqual(
            AddToLibraryViewModel.autoDetectKind(for: try XCTUnwrap(URL(string: "https://strava.com/activities/1"))),
            .workout
        )
        XCTAssertEqual(
            AddToLibraryViewModel.autoDetectKind(for: try XCTUnwrap(URL(string: "https://example.com/article"))),
            .article
        )
    }

    func testAddToLibraryPreviewSuccessAndFailureStates() async {
        let successPreview = OGPreview(
            url: URL(string: "https://example.com/workout")!,
            title: "Workout Preview",
            imageURL: nil,
            siteName: "Example"
        )
        let successFetcher = StubPreviewFetcher(result: .success(successPreview))
        var viewModel = AddToLibraryViewModel(
            urlText: "https://example.com/workout",
            previewFetcher: successFetcher,
            saver: StubKnowledgeSaver()
        )

        await viewModel.fetchPreview()

        XCTAssertEqual(viewModel.previewState, .content(successPreview))
        XCTAssertNil(viewModel.ctaError)

        let failingFetcher = StubPreviewFetcher(result: .failure(URLError(.notConnectedToInternet)))
        viewModel = AddToLibraryViewModel(
            urlText: "https://example.com/workout",
            previewFetcher: failingFetcher,
            saver: StubKnowledgeSaver()
        )

        await viewModel.fetchPreview()

        guard case .failed(let error) = viewModel.previewState else {
            return XCTFail("Expected failed preview state, got \(viewModel.previewState)")
        }
        XCTAssertEqual(viewModel.ctaError, error)
        XCTAssertEqual(viewModel.lastFailedAction, .fetchPreview)
        XCTAssertTrue(error.isRetryable)
    }

    func testAddToLibrarySaveSuccessSendsURLKindTagsAndMarksSaved() async {
        let saver = StubKnowledgeSaver()
        let viewModel = AddToLibraryViewModel(
            urlText: "example.com/workout",
            previewFetcher: StubPreviewFetcher(result: .failure(URLError(.badURL))),
            saver: saver
        )
        viewModel.selectKind(.workout)
        viewModel.tagDraft = "strength, #mobility"

        await viewModel.save()

        XCTAssertTrue(viewModel.didSave)
        XCTAssertNil(viewModel.ctaError)
        XCTAssertEqual(saver.lastURL?.absoluteString, "https://example.com/workout")
        XCTAssertEqual(saver.lastKind, .workout)
        XCTAssertEqual(saver.lastTags, ["strength", "mobility"])
    }

    func testAddToLibrarySaveErrorMatrixMapsCTAErrorAndCanRetry() async {
        let cases: [(Error, (CTAError) -> Bool, String)] = [
            (URLError(.timedOut), { if case .network(let code, _) = $0 { return code == .timedOut }; return false }, "network"),
            (APIError.serverErrorWithBody(503, "{\"detail\":\"ingest unavailable\"}"), { if case .http(let status, let body, _) = $0 { return status == 503 && (body?.contains("ingest unavailable") == true) }; return false }, "http"),
            (APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad card"))), { if case .decoding = $0 { return true }; return false }, "decoding")
        ]

        for (error, matcher, label) in cases {
            let saver = StubKnowledgeSaver(result: .failure(error))
            let viewModel = AddToLibraryViewModel(
                urlText: "https://example.com/workout",
                previewFetcher: StubPreviewFetcher(result: .failure(URLError(.badURL))),
                saver: saver
            )

            await viewModel.save()

            XCTAssertFalse(viewModel.didSave)
            guard let ctaError = viewModel.ctaError else {
                XCTFail("Expected CTAError for \(label)")
                continue
            }
            XCTAssertTrue(matcher(ctaError), "Wrong CTAError for \(label): \(ctaError)")
            XCTAssertEqual(viewModel.lastFailedAction, .save)

            saver.result = .success(Self.knowledgeCard(id: "retry-ok"))
            await viewModel.retryLastAction()
            XCTAssertTrue(viewModel.didSave)
            XCTAssertNil(viewModel.ctaError)
        }
    }

    private final class StubPreviewFetcher: OGPreviewFetching {
        let result: Result<OGPreview, Error>

        init(result: Result<OGPreview, Error>) {
            self.result = result
        }

        func fetchPreview(for url: URL) async throws -> OGPreview {
            try result.get()
        }
    }

    private final class StubKnowledgeSaver: KnowledgeCardSaving {
        var result: Result<KnowledgeCard, Error>
        private(set) var lastURL: URL?
        private(set) var lastKind: Components.Schemas.LibraryKind?
        private(set) var lastTags: [String]?

        init(result: Result<KnowledgeCard, Error> = .success(LibraryViewModelTests.knowledgeCard(id: "saved"))) {
            self.result = result
        }

        func saveLibraryCard(
            url: URL,
            kind: Components.Schemas.LibraryKind,
            tags: [String],
            preview: OGPreview?
        ) async throws -> KnowledgeCard {
            lastURL = url
            lastKind = kind
            lastTags = tags
            return try result.get()
        }
    }

    nonisolated private static func knowledgeCard(id: String) -> KnowledgeCard {
        KnowledgeCard(
            id: id,
            title: "Saved idea",
            summary: nil,
            microSummary: nil,
            keyTakeaways: [],
            sourceType: "url",
            sourceUrl: "https://example.com/workout",
            processingStatus: "pending",
            tags: [],
            visibility: nil,
            createdAt: "2026-05-29T12:00:00Z"
        )
    }

    private func item(
        id: String,
        kind: Components.Schemas.LibraryKind = .workout,
        tags: [String]? = ["strength"],
        title: String = "Saved idea"
    ) -> Components.Schemas.LibraryItem {
        Components.Schemas.LibraryItem(
            bookmarked: false,
            id: id,
            kind: kind,
            sourceDomain: "example.com",
            sourceUrl: "https://example.com/\(id)",
            tags: tags,
            thumbnailUrl: nil,
            title: title
        )
    }

    private func makeWorkout(id: String, name: String) -> Workout {
        Workout(
            id: id,
            name: name,
            sport: .strength,
            duration: 600,
            blocks: [],
            description: nil,
            source: .instagram
        )
    }
}
