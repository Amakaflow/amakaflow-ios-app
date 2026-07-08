//
//  HealthKitProvider.swift
//  AmakaFlow
//
//  Unified HealthKit abstraction layer (AMA-433).
//  Single protocol covers HRV + nutrition; one requestAuthorization() call
//  eliminates the double-prompt previously triggered by the two separate services.
//

import Foundation
import HealthKit

// MARK: - HRV data types (belong to the provider layer)

struct HealthKitHRVSample: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    /// HealthKit reports heartRateVariabilitySDNN in seconds.
    let sdnnSeconds: Double
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

// MARK: - Nutrition daily sums

struct NutritionDailySums: Equatable, Sendable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var water: Double = 0  // mL
}

// MARK: - Provider error

enum HealthKitProviderError: Error, LocalizedError, Equatable {
    case healthKitUnavailable
    case typeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable:
            return "HealthKit is not available on this device."
        case .typeUnavailable(let id):
            return "HealthKit type \(id) is not available."
        }
    }
}

// MARK: - Unified provider protocol

protocol HealthKitProviding {
    var isHealthDataAvailable: Bool { get }

    /// Atomic authorization: requests HRV read + nutrition read/write in one system prompt.
    func requestAuthorization() async throws

    // HRV
    func queryHRVSamples(start: Date, end: Date) async throws -> [HealthKitHRVSample]

    // Nutrition reads
    func fetchDailyNutritionSums(startOfDay: Date, now: Date) async -> NutritionDailySums
    func fetchMostRecentNutritionSourceName(startOfDay: Date, now: Date) async -> String?

    // Nutrition writes
    func logProtein(grams: Double, at date: Date) async throws
    func logWater(milliliters: Double, at date: Date) async throws
    func deleteAllNutritionData() async throws
}

// MARK: - Live implementation

final class LiveHealthKitProvider: HealthKitProviding {
    private let healthStore: HKHealthStore?

    var isHealthDataAvailable: Bool { healthStore != nil }

    init(healthStore: HKHealthStore? = nil) {
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? (healthStore ?? HKHealthStore()) : nil
    }

    func requestAuthorization() async throws {
        guard let healthStore else { throw HealthKitProviderError.healthKitUnavailable }
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func queryHRVSamples(start: Date, end: Date) async throws -> [HealthKitHRVSample] {
        guard let healthStore else { throw HealthKitHRVServiceError.healthKitUnavailable }
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitHRVServiceError.hrvTypeUnavailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: Self.mapHRVError(error))
                    return
                }
                let result = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthKitHRVSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sdnnSeconds: sample.quantity.doubleValue(for: .second())
                    )
                }
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
        }
    }

    func fetchDailyNutritionSums(startOfDay: Date, now: Date) async -> NutritionDailySums {
        guard let healthStore else { return NutritionDailySums() }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        async let cal = fetchSum(healthStore: healthStore, identifier: .dietaryEnergyConsumed, unit: .kilocalorie(), predicate: predicate)
        async let pro = fetchSum(healthStore: healthStore, identifier: .dietaryProtein, unit: .gram(), predicate: predicate)
        async let carb = fetchSum(healthStore: healthStore, identifier: .dietaryCarbohydrates, unit: .gram(), predicate: predicate)
        async let fat = fetchSum(healthStore: healthStore, identifier: .dietaryFatTotal, unit: .gram(), predicate: predicate)
        async let water = fetchSum(healthStore: healthStore, identifier: .dietaryWater, unit: .literUnit(with: .milli), predicate: predicate)

        let (calories, protein, carbs, fatGrams, waterMl) = await (cal, pro, carb, fat, water)
        return NutritionDailySums(calories: calories, protein: protein, carbs: carbs, fat: fatGrams, water: waterMl)
    }

    func fetchMostRecentNutritionSourceName(startOfDay: Date, now: Date) async -> String? {
        guard let healthStore,
              let quantityType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first?.sourceRevision.source.name)
            }
            healthStore.execute(query)
        }
    }

    func logProtein(grams: Double, at date: Date) async throws {
        guard let healthStore else { throw HealthKitProviderError.healthKitUnavailable }
        guard let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) else {
            throw HealthKitProviderError.typeUnavailable(HKQuantityTypeIdentifier.dietaryProtein.rawValue)
        }
        let sample = HKQuantitySample(
            type: proteinType,
            quantity: HKQuantity(unit: .gram(), doubleValue: grams),
            start: date,
            end: date
        )
        try await healthStore.save(sample)
    }

    func logWater(milliliters: Double, at date: Date) async throws {
        guard let healthStore else { throw HealthKitProviderError.healthKitUnavailable }
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            throw HealthKitProviderError.typeUnavailable(HKQuantityTypeIdentifier.dietaryWater.rawValue)
        }
        let sample = HKQuantitySample(
            type: waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters),
            start: date,
            end: date
        )
        try await healthStore.save(sample)
    }

    func deleteAllNutritionData() async throws {
        guard let healthStore else { throw HealthKitProviderError.healthKitUnavailable }
        let identifiers: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater
        ]
        let predicate = HKQuery.predicateForObjects(from: HKSource.default())
        for id in identifiers {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            try await healthStore.deleteObjects(of: quantityType, predicate: predicate)
        }
    }

    // MARK: - Private helpers

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let nutritionIds: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater
        ]
        for id in nutritionIds {
            if let quantityType = HKObjectType.quantityType(forIdentifier: id) { types.insert(quantityType) }
        }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        for id: HKQuantityTypeIdentifier in [.dietaryProtein, .dietaryWater] {
            if let quantityType = HKObjectType.quantityType(forIdentifier: id) { types.insert(quantityType) }
        }
        return types
    }

    private func fetchSum(
        healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    private static func mapHRVError(_ error: Error) -> HealthKitHRVServiceError {
        let nsError = error as NSError
        if nsError.domain == HKError.errorDomain,
           nsError.code == HKError.errorAuthorizationDenied.rawValue ||
           nsError.code == HKError.errorAuthorizationNotDetermined.rawValue {
            return .notAuthorized
        }
        return .queryFailed(error.localizedDescription)
    }
}
