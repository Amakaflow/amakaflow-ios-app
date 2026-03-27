//
//  CalendarSyncViewModel.swift
//  AmakaFlow
//
//  ViewModel for external calendar sync (AMA-1238).
//  Manages connected calendars, OAuth connect flow, manual sync, and disconnect.
//

import Combine
import Foundation
import SwiftUI

/// Model for a connected external calendar
struct ConnectedCalendar: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let provider: String
    let status: String
    let email: String?
    let lastSyncAt: String?
}

/// Response from calendar sync endpoint
struct CalendarSyncResponse {
    let syncedEvents: Int?
}

/// Available calendar providers for connection
enum CalendarProvider: String, CaseIterable, Identifiable {
    case google = "google"
    case outlook = "outlook"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google Calendar"
        case .outlook: return "Microsoft Outlook"
        }
    }

    var iconName: String {
        switch self {
        case .google: return "calendar"
        case .outlook: return "envelope.fill"
        }
    }
}

@MainActor
class CalendarSyncViewModel: ObservableObject {
    @Published var calendars: [ConnectedCalendar] = []
    @Published var isLoading = false
    @Published var isSyncing: Set<String> = []
    @Published var isConnecting = false
    @Published var errorMessage: String?
    @Published var showProviderPicker = false
    @Published var showDisconnectAlert = false
    @Published var calendarToDisconnect: ConnectedCalendar?
    @Published var lastSyncMessage: String?

    private let apiService: APIServiceProviding

    init(apiService: APIServiceProviding = APIService.shared) {
        self.apiService = apiService
    }

    /// Fetch connected calendars from the API
    func fetchCalendars() async {
        isLoading = true
        errorMessage = nil

        do {
            calendars = try await apiService.fetchConnectedCalendars()
        } catch {
            print("[CalendarSyncVM] Failed to fetch calendars: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Start the OAuth flow for a calendar provider
    func connectProvider(_ provider: CalendarProvider) async {
        isConnecting = true
        errorMessage = nil

        do {
            let authURL = try await apiService.connectCalendar(provider: provider.rawValue)
            if let url = URL(string: authURL) {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }
        } catch {
            print("[CalendarSyncVM] Failed to connect calendar: \(error)")
            errorMessage = "Failed to connect \(provider.displayName): \(error.localizedDescription)"
        }

        isConnecting = false
    }

    /// Trigger a manual sync for a specific calendar
    func syncCalendar(_ calendar: ConnectedCalendar) async {
        isSyncing.insert(calendar.id)
        errorMessage = nil

        do {
            let response = try await apiService.syncCalendar(calendarId: calendar.id)
            let eventCount = response.syncedEvents ?? 0
            lastSyncMessage = "Synced \(eventCount) event\(eventCount == 1 ? "" : "s") from \(calendar.name)"
            // Refresh the calendars list to update lastSyncAt
            await fetchCalendars()
        } catch {
            print("[CalendarSyncVM] Failed to sync calendar: \(error)")
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }

        isSyncing.remove(calendar.id)
    }

    /// Disconnect an external calendar
    func disconnectCalendar(_ calendar: ConnectedCalendar) async {
        errorMessage = nil

        do {
            try await apiService.disconnectCalendar(calendarId: calendar.id)
            calendars.removeAll { $0.id == calendar.id }
        } catch {
            print("[CalendarSyncVM] Failed to disconnect calendar: \(error)")
            errorMessage = "Failed to disconnect: \(error.localizedDescription)"
        }

        calendarToDisconnect = nil
    }

    /// Format last sync timestamp for display
    func formatLastSync(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "Never synced" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date = formatter.date(from: dateString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateString)
        }

        guard let syncDate = date else { return "Unknown" }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: syncDate, relativeTo: Date())
    }
}
