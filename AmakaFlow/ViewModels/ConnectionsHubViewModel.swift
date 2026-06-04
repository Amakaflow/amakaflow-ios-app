//
//  ConnectionsHubViewModel.swift
//  AmakaFlow
//
//  AMA-2103: live status model for the Profile → Connections hub.
//

import Combine
import Foundation
import SwiftUI

protocol ConnectionsHubStatusProviding {
    var appleWatchReachable: Bool { get }
    var appleWatchInstalled: Bool { get }
    var devicePreference: DevicePreference { get }
    var garminConnected: Bool { get }
    var garminDeviceName: String? { get }
    var telegramLinked: Bool { get }
    var telegramIdentifier: String? { get }
    var syncSummary: SyncQueueSummary { get }
    var connectedCalendars: [ConnectedCalendar] { get }
}

struct ConnectionsHubStatusSnapshot: ConnectionsHubStatusProviding, Equatable {
    var appleWatchReachable: Bool
    var appleWatchInstalled: Bool
    var devicePreference: DevicePreference
    var garminConnected: Bool
    var garminDeviceName: String?
    var telegramLinked: Bool
    var telegramIdentifier: String?
    var syncSummary: SyncQueueSummary
    var connectedCalendars: [ConnectedCalendar]

    init(
        appleWatchReachable: Bool,
        appleWatchInstalled: Bool = false,
        devicePreference: DevicePreference,
        garminConnected: Bool,
        garminDeviceName: String? = nil,
        telegramLinked: Bool,
        telegramIdentifier: String? = nil,
        syncSummary: SyncQueueSummary = .healthy,
        connectedCalendars: [ConnectedCalendar] = []
    ) {
        self.appleWatchReachable = appleWatchReachable
        self.appleWatchInstalled = appleWatchInstalled
        self.devicePreference = devicePreference
        self.garminConnected = garminConnected
        self.garminDeviceName = garminDeviceName
        self.telegramLinked = telegramLinked
        self.telegramIdentifier = telegramIdentifier
        self.syncSummary = syncSummary
        self.connectedCalendars = connectedCalendars
    }
}

enum ConnectionKind: String, CaseIterable, Identifiable {
    case appleWatch = "applewatch"
    case garmin
    case telegram
    case sync
    case calendar

    var id: String { rawValue }

    var accessibilityID: String { "af_connection_row_\(rawValue)" }

    var name: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .garmin: return "Garmin"
        case .telegram: return "Telegram"
        case .sync: return "Sync & delivery"
        case .calendar: return "Calendar"
        }
    }

    var purpose: String {
        switch self {
        case .appleWatch: return "Workouts & heart rate"
        case .garmin: return "Push workouts to your watch"
        case .telegram: return "Coach check-ins & briefings"
        case .sync: return "Workout delivery status"
        case .calendar: return "Schedule sessions"
        }
    }

    var description: String {
        switch self {
        case .appleWatch:
            return "Reads workouts, heart rate, and HRV so the coach can gauge readiness and load."
        case .garmin:
            return "Sends each session to your Garmin as a structured workout you can start from the wrist."
        case .telegram:
            return "Morning briefings, evening check-ins, and mid-day swap suggestions arrive as a chat."
        case .sync:
            return "Confirms each session reaches your watch and devices. Tap through for the delivery timeline."
        case .calendar:
            return "Drops each planned session onto your calendar so training fits around the rest of your day."
        }
    }

    var icon: String {
        switch self {
        case .appleWatch, .garmin: return "applewatch"
        case .telegram: return "paperplane.fill"
        case .sync: return "arrow.triangle.2.circlepath"
        case .calendar: return "calendar"
        }
    }

    var tint: Color {
        switch self {
        case .appleWatch: return Theme.Colors.accentGreen
        case .garmin: return Theme.Colors.garminBlue
        case .telegram: return Color(hex: "29B6F6")
        case .sync: return Theme.Colors.accentBlue
        case .calendar: return Theme.Colors.accentOrange
        }
    }

    var connectedMetaTitle: String {
        switch self {
        case .telegram: return "ACCOUNT"
        case .sync: return "DELIVERY"
        default: return "DEVICE"
        }
    }

    var offActionLabel: String {
        switch self {
        case .appleWatch: return "Connect Apple Watch"
        case .garmin: return "Connect Garmin"
        case .telegram: return "Connect Telegram"
        case .sync: return "Open Sync Dashboard"
        case .calendar: return "Connect calendar"
        }
    }

    var connectedActionLabel: String {
        switch self {
        case .appleWatch, .garmin: return "Manage device"
        case .telegram: return "Manage Telegram"
        case .sync: return "View delivery timeline"
        case .calendar: return "Manage calendars"
        }
    }
}

enum ConnectionLiveStatus: Equatable {
    case connected
    case healthy
    case off

    var isOn: Bool { self != .off }

    func pillText(for kind: ConnectionKind) -> String {
        switch self {
        case .connected: return "Connected"
        case .healthy: return "Healthy"
        case .off: return kind == .sync ? "Off" : "Connect"
        }
    }
}

struct ConnectionMetaRow: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

struct ConnectionItem: Equatable, Identifiable {
    let kind: ConnectionKind
    let status: ConnectionLiveStatus
    let meta: [ConnectionMetaRow]

    var id: String { kind.id }
    var name: String { kind.name }
    var purpose: String { kind.purpose }
    var description: String { kind.description }
    var icon: String { kind.icon }
    var tint: Color { kind.tint }
    var accessibilityID: String { kind.accessibilityID }
    var actionLabel: String { status.isOn ? kind.connectedActionLabel : kind.offActionLabel }
}

@MainActor
final class ConnectionsHubViewModel: ObservableObject {
    @Published private(set) var items: [ConnectionItem]

    init(statusProvider: ConnectionsHubStatusProviding) {
        self.items = Self.makeItems(from: statusProvider)
    }

    var connectedCount: Int {
        items.filter { $0.status.isOn }.count
    }

    var setupCount: Int {
        max(items.count - connectedCount, 0)
    }

    var summaryText: String {
        "\(connectedCount) connected · \(setupCount) to set up"
    }

    func refresh(from statusProvider: ConnectionsHubStatusProviding) {
        items = Self.makeItems(from: statusProvider)
    }

    nonisolated static func makeItems(from provider: ConnectionsHubStatusProviding) -> [ConnectionItem] {
        ConnectionKind.allCases.map { kind in
            ConnectionItem(
                kind: kind,
                status: status(for: kind, provider: provider),
                meta: meta(for: kind, provider: provider)
            )
        }
    }

    nonisolated private static func status(for kind: ConnectionKind, provider: ConnectionsHubStatusProviding) -> ConnectionLiveStatus {
        switch kind {
        case .appleWatch:
            return provider.appleWatchReachable || provider.appleWatchInstalled ? .connected : .off
        case .garmin:
            return provider.garminConnected ? .connected : .off
        case .telegram:
            return provider.telegramLinked ? .connected : .off
        case .sync:
            return provider.syncSummary.hasDeliveryIssues ? .off : .healthy
        case .calendar:
            return provider.connectedCalendars.contains(where: isConnectedCalendar) ? .connected : .off
        }
    }

    nonisolated private static func meta(for kind: ConnectionKind, provider: ConnectionsHubStatusProviding) -> [ConnectionMetaRow] {
        switch kind {
        case .appleWatch:
            return [
                ConnectionMetaRow(label: "Preference", value: provider.devicePreference.usesAppleWatch ? provider.devicePreference.title : "Not selected"),
                ConnectionMetaRow(label: "Watch app", value: provider.appleWatchInstalled ? "Installed" : "Not detected"),
                ConnectionMetaRow(label: "Reachability", value: provider.appleWatchReachable ? "Reachable now" : "Not reachable")
            ]
        case .garmin:
            return [
                ConnectionMetaRow(label: "Account", value: provider.garminConnected ? "Connected" : "Not linked"),
                ConnectionMetaRow(label: "Device", value: provider.garminDeviceName ?? "No Garmin selected")
            ]
        case .telegram:
            return [
                ConnectionMetaRow(label: "Account", value: provider.telegramIdentifier.map { "Connected to \($0)" } ?? (provider.telegramLinked ? "Connected" : "Not linked")),
                ConnectionMetaRow(label: "Briefings", value: "Morning · evening · check-ins")
            ]
        case .sync:
            return [
                ConnectionMetaRow(label: "Status", value: provider.syncSummary.hasDeliveryIssues ? "Attention needed" : "All caught up"),
                ConnectionMetaRow(label: "Queue", value: provider.syncSummary.queueSummaryText)
            ]
        case .calendar:
            let connected = provider.connectedCalendars.filter(isConnectedCalendar)
            return [
                ConnectionMetaRow(label: "Account", value: connected.first?.email ?? connected.first?.name ?? "Not linked"),
                ConnectionMetaRow(label: "Calendars", value: connected.isEmpty ? "None connected" : "\(connected.count) connected")
            ]
        }
    }

    nonisolated private static func isConnectedCalendar(_ calendar: ConnectedCalendar) -> Bool {
        switch calendar.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "connected", "active", "syncing", "synced":
            return true
        default:
            return false
        }
    }
}

extension DevicePreference {
    var usesAppleWatch: Bool {
        switch self {
        case .appleWatchPhone, .appleWatchOnly:
            return true
        case .phoneOnly, .garminPhone, .amazfitPhone:
            return false
        }
    }
}

extension SyncQueueSummary {
    static var healthy: SyncQueueSummary {
        SyncQueueSummary(pendingCount: 0, inFlightCount: 0, failedCount: 0, poisonCount: 0, lastAttemptedAt: nil, latestError: nil)
    }

    var hasDeliveryIssues: Bool {
        failedCount > 0 || poisonCount > 0 || latestError != nil
    }

    var queueSummaryText: String {
        if hasDeliveryIssues {
            return "\(failedCount + poisonCount) need attention"
        }
        if pendingCount + inFlightCount > 0 {
            return "\(pendingCount + inFlightCount) pending"
        }
        return "Nothing pending"
    }
}
