//
//  AccountSectionViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for AccountSectionViewModel (AMA-315).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class AccountSectionViewModelTests: XCTestCase {

    private var viewModel: AccountSectionViewModel!
    private var mockAPI: MockAPIService!
    private var mockPairing: MockPairingService!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI = MockAPIService()
        mockPairing = MockPairingService()
        mockPairing.configurePaired()

        let dependencies = AppDependencies(
            apiService: mockAPI,
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        viewModel = AccountSectionViewModel(dependencies: dependencies)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPI = nil
        mockPairing = nil
        try await super.tearDown()
    }

    // MARK: - Export

    func testExportData_successSetsShareSheet() async {
        mockAPI.exportUserDataResult = .success(Data("{}".utf8))

        await viewModel.exportData()

        XCTAssertNotNil(viewModel.exportedFileURL, "exportedFileURL should be set on success")
        XCTAssertTrue(viewModel.showShareSheet, "showShareSheet should be true on success")
        XCTAssertFalse(viewModel.showError, "showError should remain false on success")
    }

    func testExportData_failureSetsError() async {
        mockAPI.exportUserDataResult = .failure(APIError.serverError(500))

        await viewModel.exportData()

        XCTAssertTrue(viewModel.showError, "showError should be true on failure")
        XCTAssertNotNil(viewModel.errorMessage, "errorMessage should be set on failure")
        XCTAssertNil(viewModel.exportedFileURL, "exportedFileURL should remain nil on failure")
        XCTAssertFalse(viewModel.showShareSheet, "showShareSheet should remain false on failure")
    }

    func testExportData_isExportingResetAfterCompletion() async {
        mockAPI.exportUserDataResult = .success(Data("{}".utf8))

        await viewModel.exportData()

        XCTAssertFalse(viewModel.isExporting, "isExporting should be false after completion")
    }

    func testExportData_callsAPIService() async {
        mockAPI.exportUserDataResult = .success(Data("{}".utf8))

        await viewModel.exportData()

        XCTAssertTrue(mockAPI.exportUserDataCalled, "exportUserData should be called on apiService")
    }

    // MARK: - Delete Account

    func testDeleteAccount_successUnpairsPairingService() async {
        mockAPI.deleteAccountResult = .success(())

        await viewModel.deleteAccount()

        XCTAssertTrue(mockPairing.unpairCalled, "unpair should be called on success")
    }

    func testDeleteAccount_successCallsOnDeletedCallback() async {
        mockAPI.deleteAccountResult = .success(())
        var callbackFired = false

        await viewModel.deleteAccount { callbackFired = true }

        XCTAssertTrue(callbackFired, "onDeleted callback should fire on success")
    }

    func testDeleteAccount_failureSetsError() async {
        mockAPI.deleteAccountResult = .failure(APIError.serverError(500))

        await viewModel.deleteAccount()

        XCTAssertTrue(viewModel.showError, "showError should be true on failure")
        XCTAssertNotNil(viewModel.errorMessage, "errorMessage should be set on failure")
    }

    func testDeleteAccount_failureDoesNotUnpair() async {
        mockAPI.deleteAccountResult = .failure(APIError.serverError(500))

        await viewModel.deleteAccount()

        XCTAssertFalse(mockPairing.unpairCalled, "unpair should NOT be called when API fails")
    }

    func testDeleteAccount_failureDoesNotCallOnDeleted() async {
        mockAPI.deleteAccountResult = .failure(APIError.serverError(500))
        var callbackFired = false

        await viewModel.deleteAccount { callbackFired = true }

        XCTAssertFalse(callbackFired, "onDeleted callback should NOT fire on failure")
    }

    func testDeleteAccount_callsAPIService() async {
        mockAPI.deleteAccountResult = .success(())

        await viewModel.deleteAccount()

        XCTAssertTrue(mockAPI.deleteAccountCalled, "deleteAccount should be called on apiService")
    }
}
