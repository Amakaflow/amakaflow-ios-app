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
}
