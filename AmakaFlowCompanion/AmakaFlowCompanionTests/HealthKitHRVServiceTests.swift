//
//  HealthKitHRVServiceTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2052 Wedge C — HealthKit HRV ingestion honesty + aggregation tests.
//  AMA-433 — updated to use consolidated MockHealthKitProvider (dropped FakeHRVStore).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class HealthKitHRVServiceTests: XCTestCase {

    func testSamplesConvertSecondsToMillisecondsAggregateDailyMeanAndPost() async throws {
        let now = Self.date("2026-05-30T12:00:00Z")
        let provider = MockHealthKitProvider()
        provider.hrvSamples = [
            HealthKitHRVSample(
                startDate: Self.date("2026-05-29T06:00:00Z"),
                endDate: Self.date("2026-05-29T06:01:00Z"),
                sdnnSeconds: 0.040
            ),
            HealthKitHRVSample(
                startDate: Self.date("2026-05-29T07:00:00Z"),
                endDate: Self.date("2026-05-29T07:01:00Z"),
                sdnnSeconds: 0.060
            ),
            HealthKitHRVSample(
                startDate: Self.date("2026-05-30T06:00:00Z"),
                endDate: Self.date("2026-05-30T06:01:00Z"),
                sdnnSeconds: 0.055
            )
        ]
        let api = MockAPIService()
        let service = HealthKitHRVService(
            provider: provider,
            apiService: api,
            calendar: Self.utcCalendar,
            now: { now },
            minimumSyncInterval: 0
        )

        let result = await service.syncRecentHRV(days: 2, force: true)

        guard case .synced(let dailySamples) = result else {
            return XCTFail("Expected synced result, got \(result)")
        }
        XCTAssertTrue(provider.requestAuthorizationCalled)
        XCTAssertEqual(provider.lastHRVQueryStart, Self.date("2026-05-29T00:00:00Z"))
        XCTAssertEqual(dailySamples.map(\.sampleDate), ["2026-05-29", "2026-05-30"])
        XCTAssertEqual(dailySamples[0].hrvMilliseconds, 50, accuracy: 0.0001)
        XCTAssertEqual(dailySamples[1].hrvMilliseconds, 55, accuracy: 0.0001)

        XCTAssertEqual(api.postReadinessSampleCallCount, 2)
        XCTAssertEqual(api.lastReadinessSample?.sampleDate, "2026-05-30")
        XCTAssertEqual(api.lastReadinessSample?.hrv ?? -1, 55, accuracy: 0.0001)
        XCTAssertNil(api.lastReadinessSample?.restingHr)
        XCTAssertNil(api.lastReadinessSample?.sleepHours)
        XCTAssertNil(api.lastReadinessSample?.sleepQuality)
    }

    func testAuthorizationDeniedReturnsHonestNoDataAndPostsNothing() async throws {
        let provider = MockHealthKitProvider()
        provider.requestAuthorizationError = HealthKitHRVServiceError.notAuthorized
        let api = MockAPIService()
        let service = HealthKitHRVService(
            provider: provider,
            apiService: api,
            calendar: Self.utcCalendar,
            now: { Self.date("2026-05-30T12:00:00Z") },
            minimumSyncInterval: 0
        )

        let result = await service.syncRecentHRV(force: true)

        guard case .unauthorized(let message) = result else {
            return XCTFail("Expected unauthorized result, got \(result)")
        }
        XCTAssertTrue(message.contains("not authorized"))
        XCTAssertFalse(api.postReadinessSampleCalled)
        XCTAssertNil(provider.lastHRVQueryStart)
    }

    func testEmptyHealthKitSamplesReturnHonestEmptyAndPostNothing() async throws {
        let provider = MockHealthKitProvider()
        let api = MockAPIService()
        let service = HealthKitHRVService(
            provider: provider,
            apiService: api,
            calendar: Self.utcCalendar,
            now: { Self.date("2026-05-30T12:00:00Z") },
            minimumSyncInterval: 0
        )

        let result = await service.syncRecentHRV(force: true)

        guard case .empty(let message) = result else {
            return XCTFail("Expected empty result, got \(result)")
        }
        XCTAssertTrue(message.contains("not available"))
        XCTAssertFalse(api.postReadinessSampleCalled)
    }

    func testAggregationFiltersInvalidSamplesInsteadOfFabricatingHRV() throws {
        let samples = [
            HealthKitHRVSample(
                startDate: Self.date("2026-05-30T06:00:00Z"),
                endDate: Self.date("2026-05-30T06:01:00Z"),
                sdnnSeconds: -0.010
            ),
            HealthKitHRVSample(
                startDate: Self.date("2026-05-30T07:00:00Z"),
                endDate: Self.date("2026-05-30T07:01:00Z"),
                sdnnSeconds: .nan
            ),
            HealthKitHRVSample(
                startDate: Self.date("2026-05-30T08:00:00Z"),
                endDate: Self.date("2026-05-30T08:01:00Z"),
                sdnnSeconds: 0.750
            )
        ]

        let dailySamples = HealthKitHRVService.aggregateDailyMeans(samples: samples, calendar: Self.utcCalendar)

        XCTAssertTrue(dailySamples.isEmpty)
    }

    func testMockReadinessSampleRejectsAllEmptyLikeBackend() async throws {
        let api = MockAPIService()

        do {
            _ = try await api.postReadinessSample(
                hrv: nil,
                restingHr: nil,
                sleepHours: nil,
                sleepQuality: nil,
                sampleDate: "2026-05-30"
            )
            XCTFail("Expected all-empty readiness sample to be rejected")
        } catch let error as APIError {
            guard case .serverErrorWithBody(let status, let body) = error else {
                return XCTFail("Expected serverErrorWithBody, got \(error)")
            }
            XCTAssertEqual(status, 422)
            XCTAssertTrue(body.contains("At least one metric"))
        }
    }

    func testPostFailureDoesNotDebounceRetry() async throws {
        let now = Self.date("2026-05-30T12:00:00Z")
        let provider = MockHealthKitProvider()
        provider.hrvSamples = [
            HealthKitHRVSample(
                startDate: Self.date("2026-05-30T06:00:00Z"),
                endDate: Self.date("2026-05-30T06:01:00Z"),
                sdnnSeconds: 0.050
            )
        ]
        let api = MockAPIService()
        api.postReadinessSampleResult = .failure(APIError.serverError(503))
        let service = HealthKitHRVService(
            provider: provider,
            apiService: api,
            calendar: Self.utcCalendar,
            now: { now },
            minimumSyncInterval: 30 * 60
        )

        let failedResult = await service.syncRecentHRV(days: 1, force: true)
        guard case .failed = failedResult else {
            return XCTFail("Expected failed result, got \(failedResult)")
        }

        api.postReadinessSampleResult = nil
        let retryResult = await service.syncRecentHRV(days: 1)

        guard case .synced(let dailySamples) = retryResult else {
            return XCTFail("Expected retry to sync instead of debounce, got \(retryResult)")
        }
        XCTAssertEqual(dailySamples.count, 1)
        XCTAssertEqual(api.postReadinessSampleCallCount, 2)
    }

    private static var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func date(_ isoString: String) -> Date {
        ISO8601DateFormatter().date(from: isoString)!
    }
}
