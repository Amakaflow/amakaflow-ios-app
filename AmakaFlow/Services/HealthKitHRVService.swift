//
//  HealthKitHRVService.swift
//  AmakaFlow
//
//  AMA-2052 Wedge C — read real HealthKit HRV (SDNN) samples and write daily
//  apple_health readiness samples to the mobile BFF. No fabricated HRV.
//
//  HealthKitHRVSample and HealthKitHRVServiceError live in HealthKitProvider.swift.
//

import Foundation

struct ReadinessSampleWriteResult: Codable, Equatable, Sendable {
    let success: Bool
    let date: String
    let source: String
}

struct DailyHRVSample: Equatable, Sendable {
    let sampleDate: String
    let hrvMilliseconds: Double
}

enum HealthKitHRVSyncResult: Equatable {
    case synced([DailyHRVSample])
    case skipped(Date)
    case unavailable(String)
    case unauthorized(String)
    case empty(String)
    case failed(CTAError)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

@MainActor
final class HealthKitHRVService {
    static let shared = HealthKitHRVService()

    private let provider: HealthKitProviding
    private let apiService: APIServiceProviding
    private let calendar: Calendar
    private let now: () -> Date
    private let minimumSyncInterval: TimeInterval
    private var lastSyncAttemptAt: Date?

    init(
        provider: HealthKitProviding? = nil,
        apiService: APIServiceProviding? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian),
        now: @escaping () -> Date = Date.init,
        minimumSyncInterval: TimeInterval = 30 * 60
    ) {
        self.provider = provider ?? LiveHealthKitProvider()
        self.apiService = apiService ?? AppDependencies.current.apiService
        self.calendar = calendar
        self.now = now
        self.minimumSyncInterval = minimumSyncInterval
    }

    @discardableResult
    func syncRecentHRV(days: Int = 7, force: Bool = false) async -> HealthKitHRVSyncResult {
        let currentDate = now()
        if !force,
           let lastSyncAttemptAt,
           currentDate.timeIntervalSince(lastSyncAttemptAt) < minimumSyncInterval {
            return .skipped(lastSyncAttemptAt)
        }

        guard provider.isHealthDataAvailable else {
            lastSyncAttemptAt = currentDate
            return .unavailable("HealthKit HRV not available on this device")
        }

        do {
            try await provider.requestAuthorization()
        } catch let error as HealthKitProviderError {
            lastSyncAttemptAt = currentDate
            return .unavailable(error.localizedDescription)
        } catch {
            lastSyncAttemptAt = currentDate
            return .unauthorized("HealthKit HRV not authorized: \(error.localizedDescription)")
        }

        let clampedDays = max(1, days)
        let startOfToday = calendar.startOfDay(for: currentDate)
        let queryStart = calendar.date(byAdding: .day, value: -(clampedDays - 1), to: startOfToday) ?? startOfToday

        let rawSamples: [HealthKitHRVSample]
        do {
            rawSamples = try await provider.queryHRVSamples(start: queryStart, end: currentDate)
        } catch let error as HealthKitHRVServiceError {
            let result = authorizationResult(for: error)
            if !result.isFailure { lastSyncAttemptAt = currentDate }
            return result
        } catch {
            return .failed(CTAError.map(error))
        }

        let dailySamples = Self.aggregateDailyMeans(samples: rawSamples, calendar: calendar)
        guard !dailySamples.isEmpty else {
            lastSyncAttemptAt = currentDate
            return .empty("HealthKit HRV not available for the recent sync window")
        }

        do {
            for sample in dailySamples {
                _ = try await apiService.postReadinessSample(
                    hrv: sample.hrvMilliseconds,
                    restingHr: nil,
                    sleepHours: nil,
                    sleepQuality: nil,
                    sampleDate: sample.sampleDate
                )
            }
            lastSyncAttemptAt = currentDate
            return .synced(dailySamples)
        } catch {
            return .failed(CTAError.map(error))
        }
    }

    static func aggregateDailyMeans(
        samples: [HealthKitHRVSample],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [DailyHRVSample] {
        let validSamples = samples.filter { sample in
            sample.sdnnSeconds.isFinite && (0...0.5).contains(sample.sdnnSeconds)
        }
        let grouped = Dictionary(grouping: validSamples) { sample in
            calendar.startOfDay(for: sample.startDate)
        }

        return grouped.keys.sorted().compactMap { day in
            guard let values = grouped[day]?.map(\.sdnnSeconds), !values.isEmpty else { return nil }
            let meanSeconds = values.reduce(0, +) / Double(values.count)
            let meanMilliseconds = meanSeconds * 1_000
            return DailyHRVSample(
                sampleDate: dayKey(for: day, calendar: calendar),
                hrvMilliseconds: meanMilliseconds
            )
        }
    }

    private func authorizationResult(for error: HealthKitHRVServiceError) -> HealthKitHRVSyncResult {
        switch error {
        case .healthKitUnavailable, .hrvTypeUnavailable:
            return .unavailable(error.localizedDescription)
        case .notAuthorized:
            return .unauthorized(error.localizedDescription)
        case .queryFailed(let message):
            if message.lowercased().contains("author") {
                return .unauthorized("HealthKit HRV not authorized")
            }
            return .failed(.unknown(description: error.localizedDescription))
        }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
