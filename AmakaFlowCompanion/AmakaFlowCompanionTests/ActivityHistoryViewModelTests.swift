//
//  ActivityHistoryViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for ActivityHistoryViewModel using injected mock dependencies.
//  Added as part of AMA-344: Refactor ViewModels for Dependency Injection.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ActivityHistoryViewModelTests: XCTestCase {

    var viewModel: ActivityHistoryViewModel!
    var mockAPIService: MockAPIService!
    var mockPairingService: MockPairingService!
    var dependencies: AppDependencies!

    override func setUp() async throws {
        mockAPIService = MockAPIService()
        mockPairingService = MockPairingService()
        mockPairingService.configurePaired()

        mockAPIService.fetchCompletionsResult = .success(WorkoutCompletion.sampleData)

        dependencies = AppDependencies(
            apiService: mockAPIService,
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )

        viewModel = ActivityHistoryViewModel(dependencies: dependencies)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPIService = nil
        mockPairingService = nil
        dependencies = nil
    }

    // MARK: - Load Completions

    func testLoadCompletionsSuccessCallsAPI() async {
        await viewModel.loadCompletions()

        XCTAssertTrue(mockAPIService.fetchCompletionsCalled)
        XCTAssertFalse(viewModel.completions.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadCompletionsUsesInjectedService() async {
        // Inject a different set of completions to confirm we're using mock, not live service
        let testCompletion = WorkoutCompletion.sampleData.first!
        mockAPIService.fetchCompletionsResult = .success([testCompletion])

        await viewModel.loadCompletions()

        XCTAssertEqual(viewModel.completions.count, 1)
        XCTAssertEqual(viewModel.completions.first?.id, testCompletion.id)
    }

    func testLoadCompletionsErrorShowsMessage() async {
        mockAPIService.fetchCompletionsResult = .failure(APIError.serverError(500))

        await viewModel.loadCompletions()

        XCTAssertTrue(viewModel.completions.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadCompletionsNotPairedShowsEmpty() async {
        mockPairingService.isPaired = false

        await viewModel.loadCompletions()

        // Not authenticated — show empty, no API call
        XCTAssertTrue(viewModel.completions.isEmpty)
        XCTAssertFalse(mockAPIService.fetchCompletionsCalled)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadCompletionsResetsErrorOnRetry() async {
        // First call fails
        mockAPIService.fetchCompletionsResult = .failure(APIError.serverError(500))
        await viewModel.loadCompletions()
        XCTAssertNotNil(viewModel.errorMessage)

        // Second call succeeds
        mockAPIService.fetchCompletionsResult = .success(WorkoutCompletion.sampleData)
        await viewModel.loadCompletions()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.completions.isEmpty)
    }

    func testLoadCompletionsUnauthorizedShowsSessionExpired() async {
        mockAPIService.fetchCompletionsResult = .failure(APIError.unauthorized)

        await viewModel.loadCompletions()

        XCTAssertEqual(viewModel.errorMessage, "Session expired. Please reconnect.")
    }

    // MARK: - Filter

    func testFilterAllReturnsAllCompletions() async {
        await viewModel.loadCompletions()

        viewModel.selectedFilter = .all
        XCTAssertEqual(viewModel.filteredCompletions.count, viewModel.completions.count)
    }

    // MARK: - Demo Mode

    func testDemoModeSkipsAPICall() async {
        viewModel.useDemoMode = true

        await viewModel.loadCompletions()

        XCTAssertFalse(mockAPIService.fetchCompletionsCalled)
        XCTAssertFalse(viewModel.completions.isEmpty) // Demo loads mock data
    }
}
