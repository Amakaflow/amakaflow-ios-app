//
//  NutritionHealthKitService.swift
//  AmakaFlow
//
//  HealthKit integration for reading and writing nutrition data (AMA-1290).
//  Uses HealthKitProviding so authorization is shared atomically with HRV (AMA-433).
//

import Foundation
import Combine

/// Service for reading/writing nutrition data from HealthKit.
/// Requests read-only permissions by default; write permissions are requested
/// only when the user explicitly logs protein or water.
/// Both read and write auth delegate to HealthKitProviding.requestAuthorization()
/// which combines HRV + nutrition into one system prompt.
@MainActor
final class NutritionHealthKitService: ObservableObject {
    static let shared = NutritionHealthKitService()

    private let provider: HealthKitProviding

    @Published var isAuthorized = false
    @Published var todayCalories: Double = 0
    @Published var todayProtein: Double = 0
    @Published var todayCarbs: Double = 0
    @Published var todayFat: Double = 0
    @Published var todayWater: Double = 0 // in mL
    @Published var lastError: String?
    @Published var sourceAppName: String?

    init(provider: HealthKitProviding? = nil) {
        self.provider = provider ?? LiveHealthKitProvider()
    }

    // MARK: - Authorization

    func requestReadAuthorization() async {
        guard provider.isHealthDataAvailable else {
            lastError = "HealthKit not available on this device"
            return
        }
        do {
            try await provider.requestAuthorization()
            isAuthorized = true
        } catch {
            lastError = "Failed to authorize HealthKit: \(error.localizedDescription)"
        }
    }

    func requestWriteAuthorization() async {
        guard provider.isHealthDataAvailable else { return }
        do {
            try await provider.requestAuthorization()
            isAuthorized = true
        } catch {
            lastError = "Failed to authorize HealthKit write: \(error.localizedDescription)"
        }
    }

    // MARK: - Reading Daily Sums

    func fetchTodayNutrition() async {
        guard provider.isHealthDataAvailable && isAuthorized else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        let sums = await provider.fetchDailyNutritionSums(startOfDay: startOfDay, now: now)
        todayCalories = sums.calories
        todayProtein = sums.protein
        todayCarbs = sums.carbs
        todayFat = sums.fat
        todayWater = sums.water

        sourceAppName = await provider.fetchMostRecentNutritionSourceName(startOfDay: startOfDay, now: now)
    }

    // MARK: - Writing Data

    func logProtein(grams: Double) async -> Bool {
        do {
            try await provider.logProtein(grams: grams, at: Date())
            todayProtein += grams
            return true
        } catch {
            lastError = "Failed to log protein: \(error.localizedDescription)"
            return false
        }
    }

    func logWater(milliliters: Double) async -> Bool {
        do {
            try await provider.logWater(milliliters: milliliters, at: Date())
            todayWater += milliliters
            return true
        } catch {
            lastError = "Failed to log water: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Delete All Data

    func deleteAllNutritionData() async -> Bool {
        do {
            try await provider.deleteAllNutritionData()
            todayCalories = 0
            todayProtein = 0
            todayCarbs = 0
            todayFat = 0
            todayWater = 0
            sourceAppName = nil
            return true
        } catch {
            lastError = "Failed to delete nutrition data: \(error.localizedDescription)"
            return false
        }
    }
}
