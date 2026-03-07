//
//  CompletionDetailViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for CompletionDetailViewModel using injected mock dependencies.
//  Added as part of AMA-344: Refactor ViewModels for Dependency Injection.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class CompletionDetailViewModelTests: XCTestCase {

    var viewModel: CompletionDetailViewModel!
    var mockAPIService: MockAPIService!
    var mockPairingService: MockPairingService!
    var dependencies: AppDependencies!

    let testCompletionId = "test-completion-123"

    override func setUp() async throws {
        mockAPIService = MockAPIService()
        mockPairingService = MockPairingService()
        mockPairingService.configurePaired()

        mockAPIService.fetchCompletionDetailResult = .success(WorkoutCompletionDetail.sample)

        dependencies = AppDependencies(
            apiService: mockAPIService,
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession()
        )

        viewModel = CompletionDetailViewModel(
            completionId: testCompletionId,
            dependencies: dependencies
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPIService = nil
        mockPairingService = nil
        dependencies = nil
    }

    // MARK: - Load Detail

    func testLoadDetailSuccessCallsAPI() async {
        await viewModel.loadDetail()

        XCTAssertTrue(mockAPIService.fetchCompletionDetailCalled)
        XCTAssertNotNil(viewModel.detail)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadDetailUsesInjectedService() async {
        // Confirm the loaded detail matches what mock returns
        let sampleDetail = WorkoutCompletionDetail.sample
        mockAPIService.fetchCompletionDetailResult = .success(sampleDetail)

        await viewModel.loadDetail()

        XCTAssertEqual(viewModel.detail?.id, sampleDetail.id)
    }

    func testLoadDetailErrorShowsMessage() async {
        mockAPIService.fetchCompletionDetailResult = .failure(APIError.serverError(500))

        await viewModel.loadDetail()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        // Falls back to mock data on error
        XCTAssertNotNil(viewModel.detail)
    }

    func testLoadDetailNotFoundShowsMessage() async {
        mockAPIService.fetchCompletionDetailResult = .failure(APIError.notFound)

        await viewModel.loadDetail()

        XCTAssertEqual(viewModel.errorMessage, "Workout not found.")
    }

    func testLoadDetailNotPairedLoadsMockData() async {
        mockPairingService.isPaired = false

        await viewModel.loadDetail()

        // Not authenticated — falls back to mock data, no API call
        XCTAssertFalse(mockAPIService.fetchCompletionDetailCalled)
        XCTAssertNotNil(viewModel.detail) // Mock data is loaded
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadDetailUnauthorizedShowsSessionExpired() async {
        mockAPIService.fetchCompletionDetailResult = .failure(APIError.unauthorized)

        await viewModel.loadDetail()

        XCTAssertEqual(viewModel.errorMessage, "Session expired. Please reconnect.")
    }

    // MARK: - Computed Properties

    func testIsLoadedAfterSuccessfulLoad() async {
        await viewModel.loadDetail()

        XCTAssertTrue(viewModel.isLoaded)
    }

    func testCanSyncToStravaWhenNotSynced() async {
        mockAPIService.fetchCompletionDetailResult = .success(WorkoutCompletionDetail.sample)
        await viewModel.loadDetail()

        // If sample data has isSyncedToStrava = false
        let canSync = viewModel.canSyncToStrava
        XCTAssertEqual(canSync, !(viewModel.detail?.isSyncedToStrava ?? false))
    }

    // MARK: - Save to Library

    func testSaveToLibraryCallsAPIService() async {
        mockAPIService.syncWorkoutResult = .success(())
        await viewModel.loadDetail()

        // Only test if the VM says we can save
        guard viewModel.canSaveToLibrary else { return }

        await viewModel.saveToLibrary()

        XCTAssertTrue(mockAPIService.syncWorkoutCalled)
    }
}
