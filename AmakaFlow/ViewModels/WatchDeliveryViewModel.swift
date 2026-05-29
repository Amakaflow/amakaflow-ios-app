//
//  WatchDeliveryViewModel.swift
//  AmakaFlow
//
//  AMA-2028: Watch delivery timeline + resend CTA state.
//

import Combine
import Foundation

@MainActor
final class WatchDeliveryViewModel: ObservableObject {
    typealias WatchDeliveryStatus = Components.Schemas.WatchDeliveryStatus
    typealias WatchDeliveryState = Components.Schemas.WatchDeliveryState
    typealias WatchResendResult = Components.Schemas.WatchResendResult

    enum ScreenState: Equatable {
        case loading
        case content
        case error(CTAError)
    }

    enum FailedAction: Equatable {
        case load(workoutId: String)
        case resend(workoutId: String)
    }

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var status: WatchDeliveryStatus?
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var isResending = false
    private(set) var lastFailedAction: FailedAction?

    private let apiService: APIServiceProviding
    private let pollIntervalNanoseconds: UInt64
    private let now: () -> Date
    private var pollingTask: Task<Void, Never>?
    private var currentWorkoutId: String?

    init(
        apiService: APIServiceProviding? = nil,
        pollIntervalNanoseconds: UInt64 = 3_000_000_000,
        now: @escaping () -> Date = Date.init
    ) {
        self.apiService = apiService ?? AppDependencies.current.apiService
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.now = now
    }

    deinit {
        pollingTask?.cancel()
    }

    var canResend: Bool {
        status?.canResend == true && !isResending
    }

    var stateValue: String {
        status?.state.rawValue ?? "unknown"
    }

    var occurredAtRelativeText: String? {
        guard let occurredAt = status?.occurredAt else { return nil }
        return Self.relativeTimeText(occurredAt: occurredAt, now: now())
    }

    func load(workoutId: String) async {
        currentWorkoutId = workoutId
        cancelPolling()
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        await fetchStatus(workoutId: workoutId, failedAction: .load(workoutId: workoutId))
        if case .content = state {
            startPollingIfNeeded(workoutId: workoutId)
        }
    }

    func resend(workoutId: String? = nil) async {
        let targetWorkoutId = workoutId ?? currentWorkoutId
        guard let targetWorkoutId else { return }
        guard !isResending else { return }

        cancelPolling()
        isResending = true
        ctaError = nil
        defer { isResending = false }

        do {
            let result = try await apiService.resendWatchDelivery(workoutId: targetWorkoutId)
            if let failure = Self.ctaError(from: result) {
                ctaError = failure
                lastFailedAction = .resend(workoutId: targetWorkoutId)
                return
            }

            status = Self.generatedStatus(now: now())
            state = .content
            lastFailedAction = nil
            startPollingIfNeeded(workoutId: targetWorkoutId)
        } catch {
            ctaError = CTAError.map(error)
            lastFailedAction = .resend(workoutId: targetWorkoutId)
        }
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load(let workoutId):
            await load(workoutId: workoutId)
        case .resend(let workoutId):
            await resend(workoutId: workoutId)
        case .none:
            break
        }
    }

    func cancelPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func dismissError() {
        let currentError = ctaError
        ctaError = nil

        if case .load = lastFailedAction, let currentError {
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

    static func isTerminal(_ state: WatchDeliveryState) -> Bool {
        state == .confirmedOnDevice || state == .failed
    }

    static func displayName(for state: WatchDeliveryState) -> String {
        switch state {
        case .generated: return "Generated"
        case .pushed: return "Pushed"
        case .fetchedByWidget: return "Fetched"
        case .confirmedOnDevice: return "Confirmed"
        case .failed: return "Failed"
        }
    }

    static func relativeTimeText(occurredAt: String, now: Date = Date()) -> String? {
        guard let date = parseISO8601(occurredAt) else { return nil }
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < 60 { return "just now" }
        let minutes = elapsed / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }

    private func fetchStatus(workoutId: String, failedAction: FailedAction) async {
        do {
            let fetched = try await apiService.watchDeliveryStatus(workoutId: workoutId)
            guard !Task.isCancelled else { return }
            status = fetched
            state = .content
            ctaError = nil
            if case .load = failedAction {
                lastFailedAction = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
            lastFailedAction = failedAction
            cancelPolling()
        }
    }

    private func startPollingIfNeeded(workoutId: String) {
        guard let status, !Self.isTerminal(status.state) else { return }
        cancelPolling()

        let interval = pollIntervalNanoseconds
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await self?.pollOnce(workoutId: workoutId)
                let shouldStop = await self?.shouldStopPolling() ?? true
                if shouldStop { return }
            }
        }
    }

    private func pollOnce(workoutId: String) async {
        await fetchStatus(workoutId: workoutId, failedAction: .load(workoutId: workoutId))
    }

    private func shouldStopPolling() -> Bool {
        guard let status else { return true }
        if Self.isTerminal(status.state) {
            pollingTask = nil
            return true
        }
        if case .error = state {
            pollingTask = nil
            return true
        }
        return false
    }

    private var errorReportAction: String {
        switch lastFailedAction {
        case .load:
            return "watch_delivery_load"
        case .resend:
            return "watch_delivery_resend"
        case .none:
            return "watch_delivery_unknown"
        }
    }

    private var errorReportEndpoint: String {
        switch lastFailedAction {
        case .load(let workoutId):
            return "/v1/devices/watch-delivery/\(workoutId)"
        case .resend(let workoutId):
            return "/v1/devices/watch-delivery/\(workoutId)/resend"
        case .none:
            return "/v1/devices/watch-delivery"
        }
    }

    private static func ctaError(from result: WatchResendResult) -> CTAError? {
        guard result.success else {
            return CTAError.map(APIError.serverErrorWithBody(200, "{\"success\":false,\"message\":\"Watch delivery was not resent\"}"))
        }
        return nil
    }

    private static func generatedStatus(now: Date) -> WatchDeliveryStatus {
        WatchDeliveryStatus(
            canResend: false,
            occurredAt: iso8601OutputFormatter.string(from: now),
            state: .generated,
            subtitle: "Queued for Garmin delivery.",
            title: "Workout generated"
        )
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

    private static let iso8601OutputFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
