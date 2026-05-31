//
//  ReadinessDetailViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2054: Readiness detail sheet ViewModel coverage.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class ReadinessDetailViewModelTests: XCTestCase {
    private var api: FixtureAPIService!
    private var viewModel: ReadinessDetailViewModel!

    override func setUp() async throws {
        try await super.setUp()
        api = FixtureAPIService()
        viewModel = ReadinessDetailViewModel(apiService: api)
    }

    override func tearDown() async throws {
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testLoadSuccessMapsContentPrefsAndTrendGaps() async throws {
        await viewModel.load()

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.today?.hrv, 62.4)
        XCTAssertEqual(viewModel.pref(for: "hrv")?.source, "apple_health")
        XCTAssertEqual(viewModel.pref(for: "sleep")?.source, "apple_health")
        XCTAssertEqual(viewModel.pref(for: "rhr")?.source, "garmin")
        XCTAssertEqual(viewModel.trend?.metric, "hrv")
        XCTAssertEqual(viewModel.trend?.days, 7)
        let points = try XCTUnwrap(viewModel.trend?.points)
        XCTAssertEqual(points.count, 7)
        XCTAssertNil(points[1].value)
        XCTAssertNil(points[4].value)
        XCTAssertTrue(viewModel.hasTrendData)
        XCTAssertNil(viewModel.ctaError)
    }

    func testLoadHonestEmptyShowsEmptyState() async {
        api.readinessTodayEmpty = true
        api.readinessSourcePrefsEmpty = true
        api.readinessTrendResult = .success(Components.Schemas.ReadinessTrend(days: 7, metric: "hrv", points: []))

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.today?.hasData, false)
        XCTAssertTrue(viewModel.prefs.isEmpty)
        XCTAssertFalse(viewModel.hasTrendData)
    }

    func testLoadErrorMapsCTAErrorAndRetryReloads() async {
        api.readinessTodayResult = .failure(URLError(.notConnectedToInternet))

        await viewModel.load()

        guard case .error(let ctaError) = viewModel.state else {
            return XCTFail("Expected error state, got \(viewModel.state)")
        }
        XCTAssertEqual(viewModel.ctaError, ctaError)
        XCTAssertEqual(viewModel.lastFailedAction, .load)

        api.readinessTodayResult = .success(
            Components.Schemas.ReadinessToday(date: "2026-05-30", hasData: true, hrv: 61, restingHr: 49, sleepHours: 7.2)
        )
        await viewModel.retryLastAction()

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertNil(viewModel.ctaError)
        XCTAssertEqual(viewModel.today?.hrv, 61)
    }

    func testSetSourceSuccessPersistsAndRoundTripsThroughFixture() async throws {
        await viewModel.load()

        await viewModel.setSource(metric: "hrv", source: "garmin")

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.pref(for: "hrv")?.source, "garmin")
        XCTAssertNil(viewModel.ctaError)
        XCTAssertNil(viewModel.lastFailedAction)

        let reread = try await api.readinessSourcePrefs()
        XCTAssertEqual(reread.prefs.first { $0.metric == "hrv" }?.source, "garmin")
    }

    func testSetSourceErrorsMapCTAErrorAndKeepContentState() async {
        await viewModel.load()

        let cases: [(Error, Int)] = [
            (APIError.serverErrorWithBody(422, "{\"detail\":\"Invalid readiness source\"}"), 422),
            (APIError.serverError(503), 503)
        ]

        for (error, status) in cases {
            api.setReadinessSourcePrefResult = .failure(error)
            await viewModel.setSource(metric: "sleep", source: "manual")

            XCTAssertEqual(viewModel.state, .content)
            XCTAssertEqual(viewModel.lastFailedAction, .setSource(metric: "sleep"))
            guard let ctaError = viewModel.ctaError else {
                return XCTFail("Expected CTAError for status \(status)")
            }
            guard case .http(let mappedStatus, _, _) = ctaError else {
                return XCTFail("Expected http CTAError, got \(ctaError)")
            }
            XCTAssertEqual(mappedStatus, status)
            XCTAssertEqual(viewModel.pref(for: "sleep")?.source, "apple_health")
            viewModel.dismissError()
        }
    }

    func testSourceListContentsAndEnabledFlags() {
        let sources = ReadinessDetailViewModel.allSources

        XCTAssertEqual(sources.map(\.key), ["apple_health", "garmin", "manual", "whoop", "calculated"])
        XCTAssertEqual(sources.filter(\.enabled).map(\.key), ["apple_health", "garmin", "manual"])
        XCTAssertFalse(sources.first { $0.key == "whoop" }?.enabled ?? true)
        XCTAssertFalse(sources.first { $0.key == "calculated" }?.enabled ?? true)
        XCTAssertTrue(ReadinessDetailViewModel.isComingSoon("whoop"))
        XCTAssertTrue(ReadinessDetailViewModel.isComingSoon("calculated"))
        XCTAssertFalse(ReadinessDetailViewModel.isComingSoon("garmin"))
    }

    func testConcurrentSetSourceForSameMetricIsIgnoredWhileInFlight() async {
        api.setReadinessSourcePrefDelayNanoseconds = 150_000_000
        await viewModel.load()

        let first = Task { await viewModel.setSource(metric: "hrv", source: "garmin") }
        await Task.yield()
        await viewModel.setSource(metric: "hrv", source: "manual")
        await first.value

        XCTAssertEqual(api.setReadinessSourcePrefCallCount, 1)
        XCTAssertEqual(viewModel.pref(for: "hrv")?.source, "garmin")
        XCTAssertFalse(viewModel.sourceUpdatesInFlight.contains("hrv"))
    }

    func testLabelMapsCoverEveryKnownMetricAndSourceKey() {
        XCTAssertEqual(ReadinessDetailViewModel.metricLabel("hrv"), "HRV")
        XCTAssertEqual(ReadinessDetailViewModel.metricLabel("sleep"), "Sleep")
        XCTAssertEqual(ReadinessDetailViewModel.metricLabel("rhr"), "RHR")

        XCTAssertEqual(ReadinessDetailViewModel.sourceLabel("apple_health"), "Apple Health")
        XCTAssertEqual(ReadinessDetailViewModel.sourceLabel("garmin"), "Garmin")
        XCTAssertEqual(ReadinessDetailViewModel.sourceLabel("manual"), "Manual entry")
        XCTAssertEqual(ReadinessDetailViewModel.sourceLabel("whoop"), "WHOOP")
        XCTAssertEqual(ReadinessDetailViewModel.sourceLabel("calculated"), "Calculated")
    }
}
