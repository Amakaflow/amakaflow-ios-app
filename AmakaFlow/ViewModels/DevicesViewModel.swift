//
//  DevicesViewModel.swift
//  AmakaFlow
//
//  AMA-1996: Connected devices list state + display mapping.
//  AMA-2030: role assignment CTA state.
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
        case pair
        case remove(id: String)
        case setRoles(id: String)
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
    @Published private(set) var roleUpdatesInFlight: Set<String> = []
    private(set) var lastFailedAction: FailedAction?

    private let apiService: APIServiceProviding
    private let now: () -> Date
    private var lastPairShortCode: String?
    private var lastSetRolesRequest: (id: String, roles: [DeviceRole])?

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

    func pair(shortCode: String) async {
        let trimmedCode = shortCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        lastPairShortCode = trimmedCode
        ctaError = nil

        do {
            let result = try await apiService.pairDevice(shortCode: trimmedCode)
            if let failure = Self.ctaError(from: result) {
                ctaError = failure
                lastFailedAction = .pair
                return
            }
            await load()
        } catch {
            ctaError = CTAError.map(error)
            lastFailedAction = .pair
        }
    }

    func remove(_ device: PairedDevice) async {
        await revokeDevice(id: device.id)
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load:
            await load()
        case .pair:
            guard let lastPairShortCode else { return }
            await pair(shortCode: lastPairShortCode)
        case .remove(let id):
            await revokeDevice(id: id)
        case .setRoles(let id):
            guard let request = lastSetRolesRequest, request.id == id else { return }
            await setRoles(id: id, roles: request.roles)
        case .none:
            break
        }
    }

    func setRoles(_ device: PairedDevice, roles: [DeviceRole]) async {
        await setRoles(id: device.id, roles: roles)
    }

    func toggleRole(_ role: DeviceRole, for device: PairedDevice) async {
        let latestDevice = devices.first(where: { $0.id == device.id }) ?? device
        var roles = Set(latestDevice.roles ?? [])
        if roles.contains(role) {
            roles.remove(role)
        } else {
            roles.insert(role)
        }
        await setRoles(id: device.id, roles: Self.displayRoles.filter { roles.contains($0) })
    }

    func isSettingRoles(for device: PairedDevice) -> Bool {
        roleUpdatesInFlight.contains(device.id)
    }

    private func setRoles(id: String, roles: [DeviceRole]) async {
        guard !roleUpdatesInFlight.contains(id) else { return }
        roleUpdatesInFlight.insert(id)
        defer { roleUpdatesInFlight.remove(id) }

        ctaError = nil
        lastSetRolesRequest = (id: id, roles: roles)

        do {
            let result = try await apiService.setDeviceRoles(id: id, roles: roles)
            if let failure = Self.ctaError(from: result) {
                ctaError = failure
                lastFailedAction = .setRoles(id: id)
                return
            }
            patchDeviceRoles(id: id, roles: result.roles ?? roles)
            lastFailedAction = nil
        } catch {
            ctaError = CTAError.map(error)
            lastFailedAction = .setRoles(id: id)
        }
    }

    private func revokeDevice(id: String) async {
        ctaError = nil

        do {
            let result = try await apiService.revokeDevice(id: id)
            if let failure = Self.ctaError(from: result) {
                ctaError = failure
                lastFailedAction = .remove(id: id)
                return
            }
            await load()
        } catch {
            ctaError = CTAError.map(error)
            lastFailedAction = .remove(id: id)
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
            action: errorReportAction,
            error: ctaError,
            endpoint: errorReportEndpoint,
            userId: PairingService.shared.userProfile?.id
        )
    }

    private var errorReportAction: String {
        switch lastFailedAction {
        case .load:
            return "devices_load"
        case .pair:
            return "devices_pair"
        case .remove:
            return "devices_remove"
        case .setRoles:
            return "devices_set_roles"
        case .none:
            return "devices_unknown"
        }
    }

    private var errorReportEndpoint: String {
        switch lastFailedAction {
        case .load:
            return "/v1/devices"
        case .pair:
            return "/v1/devices/pair"
        case .remove(let id):
            return "/v1/devices/\(id)"
        case .setRoles(let id):
            return "/v1/devices/\(id)/roles"
        case .none:
            return "/v1/devices"
        }
    }

    func hasRole(_ role: DeviceRole, in device: PairedDevice) -> Bool {
        device.roles?.contains(role) == true
    }

    private func patchDeviceRoles(id: String, roles: [DeviceRole]) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let existing = devices[index]
        devices[index] = PairedDevice(
            id: existing.id,
            lastSyncAt: existing.lastSyncAt,
            model: existing.model,
            name: existing.name,
            roles: roles
        )
        state = devices.isEmpty ? .empty : .content
    }

    private static func ctaError(from result: Components.Schemas.PairDeviceResult) -> CTAError? {
        guard !result.success else { return nil }
        return CTAError.map(APIError.serverErrorWithBody(200, lyingSuccessBody(message: result.message)))
    }

    private static func ctaError(from result: Components.Schemas.DeviceRolesResult) -> CTAError? {
        guard !result.success else { return nil }
        return CTAError.map(APIError.serverErrorWithBody(200, lyingSuccessBody(message: "Device role update failed")))
    }

    private static func lyingSuccessBody(message: String?) -> String {
        var payload: [String: Any] = ["success": false]
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["message"] = message
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let body = String(data: data, encoding: .utf8) else {
            return "{\"success\":false}"
        }
        return body
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
