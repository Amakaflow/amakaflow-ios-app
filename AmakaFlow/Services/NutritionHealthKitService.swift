//
//  NutritionHealthKitService.swift
//  AmakaFlow
//
//  HealthKit integration for reading and writing nutrition data (AMA-1290).
//

import Foundation
import Combine
import HealthKit

/// Service for reading/writing nutrition data from HealthKit.
/// Requests read-only permissions by default; write permissions are requested
/// only when the user explicitly logs protein or water.
@MainActor
final class NutritionHealthKitService: ObservableObject {
    static let shared = NutritionHealthKitService()

    private let healthStore: HKHealthStore?
    private let isAvailable: Bool

    @Published var isAuthorized = false
    @Published var todayCalories: Double = 0
    @Published var todayProtein: Double = 0
    @Published var todayCarbs: Double = 0
    @Published var todayFat: Double = 0
    @Published var todayWater: Double = 0 // in mL
    @Published var lastError: String?
    @Published var sourceAppName: String?

    // MARK: - HealthKit Types

    private var readTypes: Set<HKObjectType> {
        guard let cal = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let pro = HKObjectType.quantityType(forIdentifier: .dietaryProtein),
              let carb = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let fat = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal),
              let water = HKObjectType.quantityType(forIdentifier: .dietaryWater) else {
            return []
        }
        return [cal, pro, carb, fat, water]
    }

    private var writeTypes: Set<HKSampleType> {
        guard let pro = HKObjectType.quantityType(forIdentifier: .dietaryProtein),
              let water = HKObjectType.quantityType(forIdentifier: .dietaryWater) else {
            return []
        }
        return [pro, water]
    }

    init(healthStore: HKHealthStore? = nil) {
        self.isAvailable = HKHealthStore.isHealthDataAvailable()
        self.healthStore = isAvailable ? (healthStore ?? HKHealthStore()) : nil
    }

    /// Initializer for unit tests that bypasses HealthKit entirely
    init(testing: Bool) {
        self.isAvailable = false
        self.healthStore = nil
    }

    // MARK: - Authorization

    func requestReadAuthorization() async {
        guard let store = healthStore else {
            lastError = "HealthKit not available on this device"
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            lastError = "Failed to authorize HealthKit: \(error.localizedDescription)"
            print("[NutritionHealthKitService] Auth error: \(error)")
        }
    }

    func requestWriteAuthorization() async {
        guard let store = healthStore else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            lastError = "Failed to authorize HealthKit write: \(error.localizedDescription)"
            print("[NutritionHealthKitService] Write auth error: \(error)")
        }
    }

    // MARK: - Reading Daily Sums

    func fetchTodayNutrition() async {
        guard let store = healthStore, isAuthorized else { return }

        async let cal = fetchDailySum(store: store, identifier: .dietaryEnergyConsumed, unit: .kilocalorie())
        async let pro = fetchDailySum(store: store, identifier: .dietaryProtein, unit: .gram())
        async let carb = fetchDailySum(store: store, identifier: .dietaryCarbohydrates, unit: .gram())
        async let fat = fetchDailySum(store: store, identifier: .dietaryFatTotal, unit: .gram())
        async let water = fetchDailySum(store: store, identifier: .dietaryWater, unit: .literUnit(with: .milli))

        let results = await (cal, pro, carb, fat, water)
        todayCalories = results.0
        todayProtein = results.1
        todayCarbs = results.2
        todayFat = results.3
        todayWater = results.4

        await fetchSourceApp(store: store)
    }

    private func fetchDailySum(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return 0
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    print("[NutritionHealthKitService] Query error for \(identifier.rawValue): \(error)")
                    continuation.resume(returning: 0)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchSourceApp(store: HKHealthStore) async {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, _ in
                if let sample = samples?.first {
                    let name = sample.sourceRevision.source.name
                    Task { @MainActor in
                        self?.sourceAppName = name
                    }
                }
                continuation.resume()
            }
            store.execute(query)
        }
    }

    // MARK: - Writing Data

    func logProtein(grams: Double) async -> Bool {
        guard let store = healthStore,
              let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) else {
            return false
        }

        let quantity = HKQuantity(unit: .gram(), doubleValue: grams)
        let sample = HKQuantitySample(
            type: proteinType,
            quantity: quantity,
            start: Date(),
            end: Date()
        )

        do {
            try await store.save(sample)
            todayProtein += grams
            return true
        } catch {
            lastError = "Failed to log protein: \(error.localizedDescription)"
            print("[NutritionHealthKitService] Save protein error: \(error)")
            return false
        }
    }

    func logWater(milliliters: Double) async -> Bool {
        guard let store = healthStore,
              let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            return false
        }

        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters)
        let sample = HKQuantitySample(
            type: waterType,
            quantity: quantity,
            start: Date(),
            end: Date()
        )

        do {
            try await store.save(sample)
            todayWater += milliliters
            return true
        } catch {
            lastError = "Failed to log water: \(error.localizedDescription)"
            print("[NutritionHealthKitService] Save water error: \(error)")
            return false
        }
    }

    // MARK: - Delete All Data

    func deleteAllNutritionData() async -> Bool {
        guard let store = healthStore else { return false }

        let types: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed, .dietaryProtein,
            .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater
        ]

        for identifier in types {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            let predicate = HKQuery.predicateForObjects(from: HKSource.default())

            do {
                try await store.deleteObjects(of: quantityType, predicate: predicate)
            } catch {
                print("[NutritionHealthKitService] Delete error for \(identifier.rawValue): \(error)")
                lastError = "Failed to delete nutrition data: \(error.localizedDescription)"
                return false
            }
        }

        todayCalories = 0
        todayProtein = 0
        todayCarbs = 0
        todayFat = 0
        todayWater = 0
        sourceAppName = nil
        return true
    }
}
