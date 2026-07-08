//
//  MockHealthKitProvider.swift
//  AmakaFlowCompanionTests
//
//  Shared test double for HealthKitProviding (AMA-433).
//  Replaces both FakeHRVStore (HealthKitHRVServiceTests) and
//  NutritionHealthKitService(testing:) (NutritionViewModelTests).
//

import Foundation
@testable import AmakaFlowCompanion

final class MockHealthKitProvider: HealthKitProviding {
    var isHealthDataAvailable: Bool

    // Authorization
    private(set) var requestAuthorizationCalled = false
    var requestAuthorizationError: Error?

    // HRV
    var hrvSamples: [HealthKitHRVSample] = []
    var hrvQueryError: Error?
    private(set) var lastHRVQueryStart: Date?
    private(set) var lastHRVQueryEnd: Date?

    // Nutrition reads
    var nutritionSums: NutritionDailySums = NutritionDailySums()
    var nutritionSourceName: String?

    // Nutrition writes
    var logProteinError: Error?
    var logWaterError: Error?
    var deleteAllNutritionDataError: Error?
    private(set) var loggedProteinGrams: Double?
    private(set) var loggedWaterMilliliters: Double?
    private(set) var deleteAllNutritionDataCalled = false

    init(isHealthDataAvailable: Bool = true) {
        self.isHealthDataAvailable = isHealthDataAvailable
    }

    func requestAuthorization() async throws {
        requestAuthorizationCalled = true
        if let error = requestAuthorizationError { throw error }
    }

    func queryHRVSamples(start: Date, end: Date) async throws -> [HealthKitHRVSample] {
        lastHRVQueryStart = start
        lastHRVQueryEnd = end
        if let error = hrvQueryError { throw error }
        return hrvSamples
    }

    func fetchDailyNutritionSums(startOfDay: Date, now: Date) async -> NutritionDailySums {
        return nutritionSums
    }

    func fetchMostRecentNutritionSourceName(startOfDay: Date, now: Date) async -> String? {
        return nutritionSourceName
    }

    func logProtein(grams: Double, at date: Date) async throws {
        if let error = logProteinError { throw error }
        loggedProteinGrams = grams
    }

    func logWater(milliliters: Double, at date: Date) async throws {
        if let error = logWaterError { throw error }
        loggedWaterMilliliters = milliliters
    }

    func deleteAllNutritionData() async throws {
        if let error = deleteAllNutritionDataError { throw error }
        deleteAllNutritionDataCalled = true
    }
}
