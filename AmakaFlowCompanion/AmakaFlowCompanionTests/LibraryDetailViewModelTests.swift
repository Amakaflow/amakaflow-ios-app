//
//  LibraryDetailViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2005: Library detail state, body rendering, and CTA error mapping.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class LibraryDetailViewModelTests: XCTestCase {
    private var api: MockAPIService!
    private var viewModel: LibraryDetailViewModel!

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
        viewModel = LibraryDetailViewModel(apiService: api)
    }

    override func tearDown() async throws {
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testInitialStateIsLoading() {
        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertNil(viewModel.item)
        XCTAssertNil(viewModel.ctaError)
        XCTAssertNil(viewModel.lastFailedAction)
        XCTAssertEqual(viewModel.title, "Library detail")
    }

    func testLoadArticleShowsSummaryTakeawaysAndBrowserURL() async {
        let detail = item(
            id: "article-1",
            kind: .article,
            sourceUrl: "https://example.com/article",
            summary: "Article excerpt",
            keyTakeaways: ["Read this", "Apply that"]
        )
        api.getLibraryItemResult = .success(detail)

        await viewModel.load(id: "article-1")

        XCTAssertTrue(api.getLibraryItemCalled)
        XCTAssertEqual(api.lastGetLibraryItemId, "article-1")
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.item, detail)
        XCTAssertEqual(viewModel.summaryText, "Article excerpt")
        XCTAssertEqual(viewModel.takeaways, ["Read this", "Apply that"])
        XCTAssertEqual(viewModel.sourceURL?.absoluteString, "https://example.com/article")
        XCTAssertEqual(LibraryDetailViewModel.openButtonTitle(for: .article), "Open in browser")
        XCTAssertNil(LibraryDetailViewModel.previewOnlyMessage(for: .article))
        XCTAssertNil(viewModel.ctaError)
    }

    func testLoadVideoShowsOpenVideoCopyAndRealBody() async {
        let detail = item(
            id: "video-1",
            kind: .video,
            sourceDomain: "youtube.com",
            sourceUrl: "https://youtube.com/watch?v=abc",
            summary: "Video summary",
            keyTakeaways: ["Drill one"]
        )
        api.getLibraryItemResult = .success(detail)

        await viewModel.load(id: "video-1")

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.summaryText, "Video summary")
        XCTAssertEqual(viewModel.takeaways, ["Drill one"])
        XCTAssertEqual(viewModel.sourceURL?.host, "youtube.com")
        XCTAssertEqual(LibraryDetailViewModel.openButtonTitle(for: .video), "Open video")
        XCTAssertNil(LibraryDetailViewModel.previewOnlyMessage(for: .video))
    }

    func testLoadWorkoutShowsPreviewOnlyDeferral() async {
        let detail = item(
            id: "workout-1",
            kind: .workout,
            summary: "Workout preview",
            keyTakeaways: ["Sets and reps are deferred"]
        )
        api.getLibraryItemResult = .success(detail)

        await viewModel.load(id: "workout-1")

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.summaryText, "Workout preview")
        XCTAssertEqual(viewModel.takeaways, ["Sets and reps are deferred"])
        XCTAssertEqual(
            LibraryDetailViewModel.previewOnlyMessage(for: .workout),
            "Preview only — full import coming soon"
        )
    }

    func testLoadPlanShowsPreviewOnlyDeferral() async {
        let detail = item(
            id: "plan-1",
            kind: .plan,
            summary: "Plan preview",
            keyTakeaways: ["Weeks are deferred"]
        )
        api.getLibraryItemResult = .success(detail)

        await viewModel.load(id: "plan-1")

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.summaryText, "Plan preview")
        XCTAssertEqual(viewModel.takeaways, ["Weeks are deferred"])
        XCTAssertEqual(
            LibraryDetailViewModel.previewOnlyMessage(for: .plan),
            "Preview only — full import coming soon"
        )
    }

    func testLoadEmptyWhenNoSummaryOrTakeaways() async {
        let detail = item(
            id: "empty-1",
            kind: .article,
            microSummary: "Header-only copy does not count as a body",
            summary: "   ",
            keyTakeaways: ["  "]
        )
        api.getLibraryItemResult = .success(detail)

        await viewModel.load(id: "empty-1")

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.item, detail)
        XCTAssertNil(viewModel.summaryText)
        XCTAssertTrue(viewModel.takeaways.isEmpty)
        XCTAssertFalse(LibraryDetailViewModel.hasBody(detail))
    }

    func testLoadErrorMatrixMapsToCTAErrorAndRetry() async {
        let cases: [(Error, (CTAError) -> Bool, String)] = [
            (URLError(.notConnectedToInternet), { if case .network(let code, _) = $0 { return code == .notConnectedToInternet }; return false }, "network"),
            (APIError.serverErrorWithBody(404, "{\"detail\":\"Library item not found\"}"), { if case .http(let status, let body, _) = $0 { return status == 404 && (body?.contains("Library item not found") == true) }; return false }, "404"),
            (APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad detail shape"))), { if case .decoding = $0 { return true }; return false }, "decoding")
        ]

        for (error, matcher, label) in cases {
            api = MockAPIService()
            api.getLibraryItemResult = .failure(error)
            viewModel = LibraryDetailViewModel(apiService: api)

            await viewModel.load(id: "broken-\(label)")

            guard case .error(let ctaError) = viewModel.state else {
                XCTFail("Expected error state for \(label), got \(viewModel.state)")
                continue
            }
            XCTAssertTrue(matcher(ctaError), "Wrong CTAError mapping for \(label): \(ctaError)")
            XCTAssertEqual(viewModel.ctaError, ctaError)
            XCTAssertEqual(viewModel.lastFailedAction, .load(id: "broken-\(label)"))

            let retryDetail = item(id: "retry-ok-\(label)", kind: .article)
            api.getLibraryItemResult = .success(retryDetail)
            await viewModel.retryLastAction()
            XCTAssertEqual(viewModel.state, .content)
            XCTAssertEqual(viewModel.item?.id, retryDetail.id)
            XCTAssertNil(viewModel.ctaError)
        }
    }

    func testDismissLoadErrorKeepsErrorStateInsteadOfFakeEmptyDetail() async {
        api.getLibraryItemResult = .failure(URLError(.notConnectedToInternet))

        await viewModel.load(id: "offline")
        viewModel.dismissError()

        XCTAssertNil(viewModel.ctaError)
        guard case .error = viewModel.state else {
            return XCTFail("Dismissed load error must remain in error state, got \(viewModel.state)")
        }
        XCTAssertNil(viewModel.item)
    }

    func testSourceCaptionAndSavedDateFormatting() async {
        api.getLibraryItemResult = .success(
            item(
                id: "caption",
                kind: .article,
                sourceDomain: "example.com",
                savedAt: "2026-05-29T12:10:00Z"
            )
        )

        await viewModel.load(id: "caption")

        XCTAssertTrue(viewModel.sourceCaption.contains("example.com"))
        XCTAssertTrue(viewModel.sourceCaption.contains("Saved"))
        XCTAssertEqual(viewModel.tags, ["strength", "saved"])
    }

    func testGeneratedDecoderHandlesLibraryItemDetailSchema() throws {
        let json = """
        {
          "id": "lib-detail-1",
          "title": "Saved article",
          "kind": "article",
          "sourceUrl": "https://example.com/detail",
          "sourceDomain": "example.com",
          "thumbnailUrl": null,
          "tags": ["endurance"],
          "bookmarked": false,
          "savedAt": "2026-05-29T12:00:00Z",
          "summary": "Detail summary",
          "keyTakeaways": ["One", "Two"],
          "microSummary": "Short"
        }
        """.data(using: .utf8)!

        let decoded = try APIService.makeGeneratedDecoder().decode(Components.Schemas.LibraryItemDetail.self, from: json)

        XCTAssertEqual(decoded.id, "lib-detail-1")
        XCTAssertEqual(decoded.kind, .article)
        XCTAssertEqual(decoded.summary, "Detail summary")
        XCTAssertEqual(decoded.keyTakeaways, ["One", "Two"])
        XCTAssertEqual(decoded.microSummary, "Short")
    }

    func testFixtureServiceSurfacesDetailPerKindAnd404Knob() async throws {
        let fixture = FixtureAPIService()

        let workout = try await fixture.getLibraryItem(id: "fixture-strength-basics")
        let video = try await fixture.getLibraryItem(id: "fixture-ankle-mobility-video")
        let article = try await fixture.getLibraryItem(id: "fixture-zone-two-article")
        let plan = try await fixture.getLibraryItem(id: "fixture-hyrox-plan")

        XCTAssertEqual(Set([workout.kind, video.kind, article.kind, plan.kind]), [.workout, .video, .article, .plan])
        XCTAssertTrue([workout, video, article, plan].allSatisfy { LibraryDetailViewModel.hasBody($0) })

        fixture.libraryItemDetail404 = true
        do {
            _ = try await fixture.getLibraryItem(id: "fixture-strength-basics")
            XCTFail("Expected fixture 404 knob to throw")
        } catch {
            guard case APIError.serverErrorWithBody(let status, _) = error else {
                return XCTFail("Expected raw APIError.serverErrorWithBody, got \(error)")
            }
            XCTAssertEqual(status, 404)
        }
    }

    private func item(
        id: String,
        kind: Components.Schemas.LibraryKind,
        sourceDomain: String? = "example.com",
        sourceUrl: String? = "https://example.com/\(UUID().uuidString)",
        savedAt: String? = "2026-05-29T12:00:00Z",
        microSummary: String? = "Short summary",
        summary: String? = "A useful saved item summary.",
        keyTakeaways: [String]? = ["Takeaway"],
        tags: [String]? = ["strength", "saved"],
        title: String = "Saved item"
    ) -> Components.Schemas.LibraryItemDetail {
        Components.Schemas.LibraryItemDetail(
            bookmarked: false,
            id: id,
            keyTakeaways: keyTakeaways,
            kind: kind,
            microSummary: microSummary,
            savedAt: savedAt,
            sourceDomain: sourceDomain,
            sourceUrl: sourceUrl,
            summary: summary,
            tags: tags,
            thumbnailUrl: nil,
            title: title
        )
    }
}
