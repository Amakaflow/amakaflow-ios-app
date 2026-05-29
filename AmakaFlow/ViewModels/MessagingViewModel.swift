//
//  MessagingViewModel.swift
//  AmakaFlow
//
//  AMA-2027: Messaging channels + coaching-delivery preferences.
//

import Combine
import Foundation

@MainActor
final class MessagingViewModel: ObservableObject {
    typealias MessagingChannel = Components.Schemas.MessagingChannel
    typealias ChannelPrefs = Components.Schemas.ChannelPrefs
    typealias ChannelPrefsRequest = Components.Schemas.ChannelPrefsRequest

    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    enum FailedAction: Equatable {
        case load
        case setPrefs(channelId: String, prefs: ChannelPrefsRequest)
    }

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var channels: [MessagingChannel] = []
    @Published private(set) var deliveryLive = false
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var prefUpdatesInFlight: Set<String> = []
    private(set) var lastFailedAction: FailedAction?

    private let apiService: APIServiceProviding

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
    }

    var connectedSubtitle: String {
        let connectedCount = channels.filter { $0.connected == true }.count
        if channels.isEmpty { return "No channels" }
        return "\(connectedCount) connected"
    }

    func load() async {
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        do {
            let response = try await apiService.listMessagingChannels()
            channels = response.channels ?? []
            deliveryLive = response.deliveryLive == true
            state = channels.isEmpty ? .empty : .content
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
            lastFailedAction = .load
        }
    }

    func setPrefs(_ channel: MessagingChannel, prefs: ChannelPrefsRequest) async {
        await setPrefs(channelId: channel.id, prefs: prefs)
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load:
            await load()
        case .setPrefs(let channelId, let prefs):
            await setPrefs(channelId: channelId, prefs: prefs)
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
            action: errorReportAction,
            error: ctaError,
            endpoint: errorReportEndpoint,
            userId: PairingService.shared.userProfile?.id
        )
    }

    func isSettingPrefs(for channel: MessagingChannel) -> Bool {
        prefUpdatesInFlight.contains(channel.id)
    }

    func prefsRequest(
        from channel: MessagingChannel,
        briefing: Bool? = nil,
        checkin: Bool? = nil,
        swap: Bool? = nil,
        quietStart: String? = nil,
        quietEnd: String? = nil
    ) -> ChannelPrefsRequest {
        let prefs = channel.prefs
        return ChannelPrefsRequest(
            briefing: briefing ?? prefs?.briefing ?? false,
            checkin: checkin ?? prefs?.checkin ?? false,
            quietEnd: quietEnd ?? prefs?.quietEnd,
            quietStart: quietStart ?? prefs?.quietStart,
            swap: swap ?? prefs?.swap ?? false
        )
    }

    func isConnected(_ channel: MessagingChannel) -> Bool {
        channel.connected == true
    }

    func isComingSoon(_ channel: MessagingChannel) -> Bool {
        channel.comingSoon == true
    }

    func canEditPrefs(for channel: MessagingChannel) -> Bool {
        isConnected(channel) && !isComingSoon(channel) && !isSettingPrefs(for: channel)
    }

    static func boolPref(_ keyPath: KeyPath<ChannelPrefs, Bool?>, in channel: MessagingChannel) -> Bool {
        channel.prefs?[keyPath: keyPath] == true
    }

    static func channelStatus(_ channel: MessagingChannel) -> String {
        if channel.comingSoon == true { return "Coming soon" }
        if channel.connected == true { return "Connected" }
        return "Not connected"
    }

    static func quietLabel(start: String?, end: String?) -> String {
        guard let start, !start.isEmpty, let end, !end.isEmpty else { return "Off" }
        return "\(start)–\(end)"
    }

    private func setPrefs(channelId: String, prefs: ChannelPrefsRequest) async {
        guard !prefUpdatesInFlight.contains(channelId) else { return }
        prefUpdatesInFlight.insert(channelId)
        defer { prefUpdatesInFlight.remove(channelId) }

        if case .setPrefs(let failedChannelId, _) = lastFailedAction,
           failedChannelId == channelId {
            ctaError = nil
        }

        do {
            let result = try await apiService.setChannelPrefs(channelId: channelId, prefs: prefs)
            if let failure = Self.ctaError(from: result) {
                ctaError = failure
                lastFailedAction = .setPrefs(channelId: channelId, prefs: prefs)
                return
            }
            patchChannelPrefs(channelId: result.channelId, prefs: result.prefs ?? Self.channelPrefs(from: prefs))
            clearFailedPrefsIfCurrent(channelId: channelId)
        } catch {
            ctaError = CTAError.map(error)
            lastFailedAction = .setPrefs(channelId: channelId, prefs: prefs)
        }
    }

    private func clearFailedPrefsIfCurrent(channelId: String) {
        guard case .setPrefs(let failedChannelId, _) = lastFailedAction,
              failedChannelId == channelId else { return }
        lastFailedAction = nil
        ctaError = nil
    }

    private func patchChannelPrefs(channelId: String, prefs: ChannelPrefs) {
        guard let index = channels.firstIndex(where: { $0.id == channelId }) else { return }
        let existing = channels[index]
        channels[index] = MessagingChannel(
            comingSoon: existing.comingSoon,
            connected: existing.connected,
            handle: existing.handle,
            id: existing.id,
            name: existing.name,
            prefs: prefs
        )
        state = channels.isEmpty ? .empty : .content
    }

    private var errorReportAction: String {
        switch lastFailedAction {
        case .load:
            return "messaging_channels_load"
        case .setPrefs(_, _):
            return "messaging_channels_set_prefs"
        case .none:
            return "messaging_channels_unknown"
        }
    }

    private var errorReportEndpoint: String {
        switch lastFailedAction {
        case .load:
            return "/v1/messaging/channels"
        case .setPrefs(let channelId, _):
            return "/v1/messaging/channels/\(channelId)/prefs"
        case .none:
            return "/v1/messaging/channels"
        }
    }

    private static func ctaError(from result: Components.Schemas.ChannelPrefsResult) -> CTAError? {
        guard !result.success else { return nil }
        return CTAError.map(APIError.serverErrorWithBody(200, lyingSuccessBody(message: "Messaging preferences were not saved")))
    }

    private static func channelPrefs(from request: ChannelPrefsRequest) -> ChannelPrefs {
        ChannelPrefs(
            briefing: request.briefing,
            checkin: request.checkin,
            quietEnd: request.quietEnd,
            quietStart: request.quietStart,
            swap: request.swap
        )
    }

    private static func lyingSuccessBody(message: String) -> String {
        let payload: [String: Any] = ["success": false, "message": message]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let body = String(data: data, encoding: .utf8) else {
            return "{\"success\":false}"
        }
        return body
    }
}
