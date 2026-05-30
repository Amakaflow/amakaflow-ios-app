//
//  HealthKitHRVService.swift
//  AmakaFlow
//
//  AMA-2052 Wedge C — read real HealthKit HRV (SDNN) samples and write daily
//  apple_health readiness samples to the mobile BFF. No fabricated HRV.
//

import Foundation
import HealthKit

struct ReadinessSampleWriteResult: Codable, Equatable, Sendable {
    let success: Bool
    let date: String
    let source: String
}

struct DailyHRVSample: Equatable, Sendable {
    let sampleDate: String
    let hrvMilliseconds: Double
}

struct HealthKitHRVSample: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    /// HealthKit reports heartRateVariabilitySDNN in seconds.
    let sdnnSeconds: Double
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

enum HealthKitHRVServiceError: Error, LocalizedError, Equatable {
    case healthKitUnavailable
    case hrvTypeUnavailable
    case notAuthorized
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable:
            return "HealthKit HRV is not available on this device."
        case .hrvTypeUnavailable:
            return "HealthKit HRV sample type is not available."
        case .notAuthorized:
            return "HealthKit HRV is not authorized."
        case .queryFailed(let message):
            return "HealthKit HRV query failed: \(message)"
        }
    }
}

protocol HealthKitHRVStoreProviding {
    var isHealthDataAvailable: Bool { get }
    func requestHRVReadAuthorization() async throws
    func queryHRVSamples(start: Date, end: Date) async throws -> [HealthKitHRVSample]
}

final class LiveHealthKitHRVStore: HealthKitHRVStoreProviding {
    private let healthStore: HKHealthStore?

    var isHealthDataAvailable: Bool { healthStore != nil }

    init(healthStore: HKHealthStore? = nil) {
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? (healthStore ?? HKHealthStore()) : nil
    }

    func requestHRVReadAuthorization() async throws {
        guard let healthStore else { throw HealthKitHRVServiceError.healthKitUnavailable }
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitHRVServiceError.hrvTypeUnavailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: [hrvType])
    }

    func queryHRVSamples(start: Date, end: Date) async throws -> [HealthKitHRVSample] {
        guard let healthStore else { throw HealthKitHRVServiceError.healthKitUnavailable }
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitHRVServiceError.hrvTypeUnavailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: Self.map(error))
                    return
                }

                let hrvSamples = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthKitHRVSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sdnnSeconds: sample.quantity.doubleValue(for: .second())
                    )
                }
                continuation.resume(returning: hrvSamples)
            }
            healthStore.execute(query)
        }
    }

    private static func map(_ error: Error) -> HealthKitHRVServiceError {
        let nsError = error as NSError
        if nsError.domain == HKError.errorDomain,
           nsError.code == HKError.errorAuthorizationDenied.rawValue || nsError.code == HKError.errorAuthorizationNotDetermined.rawValue {
            return .notAuthorized
        }
        return .queryFailed(error.localizedDescription)
    }
}

@MainActor
final class HealthKitHRVService {
    static let shared = HealthKitHRVService()

    private let store: HealthKitHRVStoreProviding
    private let apiService: APIServiceProviding
    private let calendar: Calendar
    private let now: () -> Date
    private let minimumSyncInterval: TimeInterval
    private var lastSyncAttemptAt: Date?

    init(
        store: HealthKitHRVStoreProviding? = nil,
        apiService: APIServiceProviding? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian),
        now: @escaping () -> Date = Date.init,
        minimumSyncInterval: TimeInterval = 30 * 60
    ) {
        self.store = store ?? LiveHealthKitHRVStore()
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

        guard store.isHealthDataAvailable else {
            lastSyncAttemptAt = currentDate
            return .unavailable("HealthKit HRV not available on this device")
        }

        do {
            try await store.requestHRVReadAuthorization()
        } catch let error as HealthKitHRVServiceError {
            let result = authorizationResult(for: error)
            if !result.isFailure { lastSyncAttemptAt = currentDate }
            return result
        } catch {
            lastSyncAttemptAt = currentDate
            return .unauthorized("HealthKit HRV not authorized: \(error.localizedDescription)")
        }

        let clampedDays = max(1, days)
        let startOfToday = calendar.startOfDay(for: currentDate)
        let queryStart = calendar.date(byAdding: .day, value: -(clampedDays - 1), to: startOfToday) ?? startOfToday

        let rawSamples: [HealthKitHRVSample]
        do {
            rawSamples = try await store.queryHRVSamples(start: queryStart, end: currentDate)
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
