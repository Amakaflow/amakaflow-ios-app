//
//  ReadinessDetailViewModel.swift
//  AmakaFlow
//
//  AMA-2054: Readiness detail sheet state + per-metric source picker.
//

import Combine
import Foundation

@MainActor
final class ReadinessDetailViewModel: ObservableObject {
    typealias ReadinessToday = Components.Schemas.ReadinessToday
    typealias ReadinessTrend = Components.Schemas.ReadinessTrend
    typealias ReadinessTrendPoint = Components.Schemas.ReadinessTrendPoint
    typealias ReadinessSourcePref = Components.Schemas.ReadinessSourcePref
    typealias ReadinessSourcePrefs = Components.Schemas.ReadinessSourcePrefs

    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    enum FailedAction: Equatable {
        case load
        case setSource(metric: String)
    }

    struct SourceOption: Identifiable, Equatable {
        let key: String
        let label: String
        let enabled: Bool

        var id: String { key }
    }

    struct MetricRow: Identifiable, Equatable {
        let key: String
        let label: String
        let valueText: String
        let sourceKey: String?
        let sourceCaption: String
        let hasValue: Bool
        let isUpdating: Bool

        var id: String { key }
    }

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var today: ReadinessToday?
    @Published private(set) var trend: ReadinessTrend?
    @Published private(set) var prefs: [ReadinessSourcePref] = []
    @Published private(set) var sourceUpdatesInFlight: Set<String> = []
    private(set) var lastFailedAction: FailedAction?

    private let apiService: APIServiceProviding
    private var lastSetSourceRequest: (metric: String, source: String)?

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
    }

    var headerSubtitle: String {
        switch state {
        case .loading:
            return "Loading metrics"
        case .content:
            return "HRV, sleep, and RHR"
        case .empty:
            return "Connect a recovery device"
        case .error:
            return "Unable to load"
        }
    }

    var metricRows: [MetricRow] {
        Self.metrics.map { metric in
            let sourceKey = sourceKey(for: metric)
            return MetricRow(
                key: metric,
                label: Self.metricLabel(metric),
                valueText: valueText(for: metric),
                sourceKey: sourceKey,
                sourceCaption: "Source: \(sourceKey.map(Self.sourceLabel) ?? "Not set")",
                hasValue: hasMetricValue(metric),
                isUpdating: sourceUpdatesInFlight.contains(metric)
            )
        }
    }

    var hasTrendData: Bool {
        trend?.points?.contains { $0.value != nil } == true
    }

    func load() async {
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        do {
            async let fetchedToday = apiService.readinessToday()
            async let fetchedPrefs = apiService.readinessSourcePrefs()
            async let fetchedTrend = apiService.readinessTrend(metric: "hrv", days: 7)

            let (today, prefs, trend) = try await (fetchedToday, fetchedPrefs, fetchedTrend)
            self.today = today
            self.prefs = prefs.prefs
            self.trend = trend
            state = hasAnyContent(today: today, prefs: prefs.prefs, trend: trend) ? .content : .empty
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
            lastFailedAction = .load
        }
    }

    func setSource(metric: String, source: String) async {
        guard !sourceUpdatesInFlight.contains(metric) else { return }
        guard Self.allSources.first(where: { $0.key == source })?.enabled == true else { return }

        sourceUpdatesInFlight.insert(metric)
        defer { sourceUpdatesInFlight.remove(metric) }

        ctaError = nil
        lastSetSourceRequest = (metric: metric, source: source)

        do {
            let updated = try await apiService.setReadinessSourcePref(metric: metric, source: source, deviceId: nil)
            patchPref(updated)
            lastFailedAction = nil
            if hasAnyContent(today: today, prefs: prefs, trend: trend) {
                state = .content
            }
        } catch {
            ctaError = CTAError.map(error)
            lastFailedAction = .setSource(metric: metric)
        }
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load:
            await load()
        case .setSource(let metric):
            guard let lastSetSourceRequest, lastSetSourceRequest.metric == metric else { return }
            await setSource(metric: lastSetSourceRequest.metric, source: lastSetSourceRequest.source)
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

    func pref(for metric: String) -> ReadinessSourcePref? {
        prefs.first { $0.metric == metric }
    }

    func sourceKey(for metric: String) -> String? {
        pref(for: metric)?.source ?? fallbackSourceKey
    }

    func isSourceSelected(_ source: String, for metric: String) -> Bool {
        sourceKey(for: metric) == source
    }

    static var allSources: [SourceOption] {
        [
            SourceOption(key: "apple_health", label: "Apple Health", enabled: true),
            SourceOption(key: "garmin", label: "Garmin", enabled: true),
            SourceOption(key: "manual", label: "Manual entry", enabled: true),
            SourceOption(key: "whoop", label: "WHOOP", enabled: false),
            SourceOption(key: "calculated", label: "Calculated", enabled: false)
        ]
    }

    static func isComingSoon(_ key: String) -> Bool {
        allSources.first(where: { $0.key == key })?.enabled == false
    }

    static func sourceLabel(_ key: String) -> String {
        switch key {
        case "apple_health": return "Apple Health"
        case "garmin": return "Garmin"
        case "manual": return "Manual entry"
        case "whoop": return "WHOOP"
        case "calculated": return "Calculated"
        default: return key
        }
    }

    static func metricLabel(_ key: String) -> String {
        switch key {
        case "hrv": return "HRV"
        case "sleep": return "Sleep"
        case "rhr": return "RHR"
        default: return key.uppercased()
        }
    }

    static let metrics = ["hrv", "sleep", "rhr"]

    private var fallbackSourceKey: String? {
        guard let source = today?.source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return source
    }

    private var errorReportAction: String {
        switch lastFailedAction {
        case .load:
            return "readiness_load"
        case .setSource:
            return "readiness_set_source"
        case .none:
            return "readiness_unknown"
        }
    }

    private var errorReportEndpoint: String {
        switch lastFailedAction {
        case .load:
            return "/v1/readiness"
        case .setSource:
            return "/v1/readiness/source-prefs"
        case .none:
            return "/v1/readiness"
        }
    }

    private func patchPref(_ updated: ReadinessSourcePref) {
        if let index = prefs.firstIndex(where: { $0.metric == updated.metric }) {
            prefs[index] = updated
        } else {
            prefs.append(updated)
        }
    }

    private func valueText(for metric: String) -> String {
        guard let today, today.hasData != false else { return "No data yet" }
        switch metric {
        case "hrv":
            guard let hrv = today.hrv else { return "No data yet" }
            return "\(Int(hrv.rounded())) ms"
        case "sleep":
            guard let sleepHours = today.sleepHours else { return "No data yet" }
            return String(format: "%.1f h", sleepHours)
        case "rhr":
            guard let restingHr = today.restingHr else { return "No data yet" }
            return "\(restingHr) bpm"
        default:
            return "No data yet"
        }
    }

    private func hasMetricValue(_ metric: String) -> Bool {
        guard let today, today.hasData != false else { return false }
        switch metric {
        case "hrv": return today.hrv != nil
        case "sleep": return today.sleepHours != nil
        case "rhr": return today.restingHr != nil
        default: return false
        }
    }

    private func hasAnyContent(today: ReadinessToday?, prefs: [ReadinessSourcePref], trend: ReadinessTrend?) -> Bool {
        if let today, today.hasData == true || today.hrv != nil || today.sleepHours != nil || today.restingHr != nil || today.sleepQuality != nil {
            return true
        }
        if !prefs.isEmpty {
            return true
        }
        return trend?.points?.contains { $0.value != nil } == true
    }
}
