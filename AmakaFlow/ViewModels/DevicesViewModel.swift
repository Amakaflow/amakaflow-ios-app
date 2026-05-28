//
//  DevicesViewModel.swift
//  AmakaFlow
//
//  AMA-1996: Connected devices read-only list state + display mapping.
//

import Combine
import Foundation

@MainActor
final class DevicesViewModel: ObservableObject {
    typealias PairedDevice = Components.Schemas.PairedDevice
    typealias DeviceRole = Components.Schemas.DeviceRole

    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    enum FailedAction: Equatable {
        case load
    }

    struct DisplayDevice: Identifiable, Equatable {
        let device: PairedDevice
        let syncCaption: String
        let modelSyncCaption: String
        let symbolName: String

        var id: String { device.id }
        var name: String { device.name }
        var model: String? { device.model }
        var roles: [DeviceRole] { device.roles ?? [] }
    }

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var devices: [PairedDevice] = []
    private(set) var lastFailedAction: FailedAction?

    private let apiService: APIServiceProviding
    private let now: () -> Date

    init(
        apiService: APIServiceProviding? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.apiService = apiService ?? AppDependencies.current.apiService
        self.now = now
    }

    var connectedSubtitle: String {
        "\(devices.count) connected"
    }

    var displayDevices: [DisplayDevice] {
        // Capture one "now" per render pass so every row's "synced X ago"
        // caption is computed against the same instant (consistent rows).
        let currentNow = now()
        return devices.map { device in
            let relative = Self.relativeSyncText(lastSyncAt: device.lastSyncAt, now: currentNow)
            return DisplayDevice(
                device: device,
                syncCaption: relative,
                modelSyncCaption: Self.modelSyncCaption(model: device.model, relativeSyncText: relative),
                symbolName: Self.symbolName(for: device)
            )
        }
    }

    func load() async {
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        do {
            let fetched = try await apiService.listDevices()
            devices = fetched
            state = fetched.isEmpty ? .empty : .content
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
            lastFailedAction = .load
        }
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load:
            await load()
        case .none:
            break
        }
    }

    func dismissError() {
        let currentError = ctaError
        ctaError = nil

        if lastFailedAction == .load, let currentError {
            state = .error(currentError)
        }
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: "devices_load",
            error: ctaError,
            endpoint: "/v1/devices",
            userId: PairingService.shared.userProfile?.id
        )
    }

    func hasRole(_ role: DeviceRole, in device: PairedDevice) -> Bool {
        device.roles?.contains(role) == true
    }

    static var displayRoles: [DeviceRole] {
        [.workouts, .recovery, .strength]
    }

    static func roleLabel(_ role: DeviceRole) -> String {
        switch role {
        case .workouts: return "Workouts"
        case .recovery: return "Recovery"
        case .strength: return "Strength"
        }
    }

    static func relativeSyncText(lastSyncAt: String?, now: Date = Date()) -> String {
        guard let lastSyncAt, let date = parseISO8601(lastSyncAt) else {
            return "—"
        }

        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < 60 {
            return "now"
        }
        let minutes = elapsed / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        let days = hours / 24
        return "\(days)d ago"
    }

    static func modelSyncCaption(model: String?, relativeSyncText: String) -> String {
        let sync = "SYNCED \(relativeSyncText.uppercased())"
        guard let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return sync
        }
        return "\(model.uppercased()) · \(sync)"
    }

    static func symbolName(for device: PairedDevice) -> String {
        let haystack = "\(device.name) \(device.model ?? "")".lowercased()
        if haystack.contains("whoop") || haystack.contains("heart") || haystack.contains("hrv") {
            return "heart.fill"
        }
        if haystack.contains("garmin") || haystack.contains("forerunner") || haystack.contains("fenix") || haystack.contains("epix") {
            return "watchface.applewatch.case"
        }
        if haystack.contains("apple") || haystack.contains("watch") {
            return "applewatch"
        }
        return "watch"
    }

    private static func parseISO8601(_ value: String) -> Date? {
        if let date = iso8601Formatter.date(from: value) {
            return date
        }
        return iso8601FractionalFormatter.date(from: value)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
