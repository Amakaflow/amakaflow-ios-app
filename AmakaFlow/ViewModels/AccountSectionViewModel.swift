//
//  AccountSectionViewModel.swift
//  AmakaFlow
//
//  Section ViewModel for account and data-export actions in SettingsView.
//  Extracted from the 2,981-line SettingsView as part of AMA-315.
//

import Combine
import Foundation
import SwiftUI

/// Manages account actions (data export, account deletion, sign-out) for the Settings screen.
/// Sits behind the AppDependencies seam so all async operations are fully unit-testable.
@MainActor
final class AccountSectionViewModel: ObservableObject {

    // MARK: - Export state

    @Published var isExporting = false
    @Published var exportedFileURL: URL?
    @Published var showShareSheet = false

    // MARK: - Error state

    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Alert / dialog state

    @Published var showDeleteConfirm = false
    @Published var showSignOutAlert = false
    @Published var showDisconnectAlert = false

    // MARK: - Dependencies

    private let apiService: APIServiceProviding
    private let pairingService: PairingServiceProviding

    init(dependencies: AppDependencies = .current) {
        self.apiService = dependencies.apiService
        self.pairingService = dependencies.pairingService
    }

    // MARK: - Actions

    /// Export the user's data and present the system share sheet.
    func exportData() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await apiService.exportUserData()
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("amakaflow-data-export.json")
            try data.write(to: tempURL, options: .atomic)
            exportedFileURL = tempURL
            showShareSheet = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Delete the account, unpair the device, and revoke biometric consent.
    /// Calls `onDeleted` on success so callers can clear local caches (e.g. TelegramLinkCache).
    func deleteAccount(onDeleted: (() -> Void)? = nil) async {
        do {
            try await apiService.deleteAccount()
            pairingService.unpair()
            UserDefaults.standard.set(false, forKey: DefaultsKey.biometricConsent.rawValue)
            onDeleted?()
        } catch {
            errorMessage = "Account deletion failed: \(error.localizedDescription)"
            showError = true
        }
    }
}
