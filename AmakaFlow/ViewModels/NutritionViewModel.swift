//
//  NutritionViewModel.swift
//  AmakaFlow
//
//  Manages all nutrition state including settings, tracking, and display (AMA-1291).
//

import Foundation
import Combine
import SwiftUI

// MARK: - Nutrition Display Mode

enum NutritionDisplayMode: String, CaseIterable, Codable {
    case qualitative = "qualitative"
    case proteinOnly = "protein_only"
    case fullMacros = "full_macros"
    case caloriesAndMacros = "calories_and_macros"

    var title: String {
        switch self {
        case .qualitative: return "Qualitative only"
        case .proteinOnly: return "Protein only"
        case .fullMacros: return "Full macros"
        case .caloriesAndMacros: return "Calories + macros"
        }
    }

    var description: String {
        switch self {
        case .qualitative: return "Shows labels like \"Well fueled\" without numbers"
        case .proteinOnly: return "Shows protein progress toward your target"
        case .fullMacros: return "Shows protein, carbs, and fat"
        case .caloriesAndMacros: return "Shows calories plus all macros"
        }
    }
}

// MARK: - Nutrition Settings

struct NutritionSettings: Codable, Equatable {
    var isEnabled: Bool
    var displayMode: NutritionDisplayMode
    var proteinTargetGrams: Double
    var waterTargetML: Double
    var hasCompletedOnboarding: Bool

    static let `default` = NutritionSettings(
        isEnabled: false,
        displayMode: .qualitative,
        proteinTargetGrams: 120,
        waterTargetML: 2500,
        hasCompletedOnboarding: false
    )
}

// MARK: - ViewModel

@MainActor
final class NutritionViewModel: ObservableObject {
    @Published var settings: NutritionSettings {
        didSet {
            if settingsLoaded { saveSettings() }
        }
    }
    @Published var todayCalories: Double = 0
    @Published var todayProtein: Double = 0
    @Published var todayCarbs: Double = 0
    @Published var todayFat: Double = 0
    @Published var todayWater: Double = 0
    @Published var sourceAppName: String?
    @Published var isLoading = false
    @Published var showOnboarding = false

    private let healthKitService: NutritionHealthKitService
    private let settingsKey = "nutrition_settings"
    private var settingsLoaded = false

    // MARK: - Init

    init(healthKitService: NutritionHealthKitService = .shared) {
        self.healthKitService = healthKitService
        self.settings = NutritionSettings.default
        loadSettings()
        settingsLoaded = true
    }

    /// Test-only initializer with explicit settings
    init(settings: NutritionSettings, healthKitService: NutritionHealthKitService) {
        self.healthKitService = healthKitService
        self.settings = settings
        settingsLoaded = true
    }

    // MARK: - Persistence

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(NutritionSettings.self, from: data) else {
            return
        }
        settings = decoded
    }

    /// AMA-1636: each consumer creates its own `@StateObject NutritionViewModel()`
    /// instance, so a toggle in NutritionSettingsView persists to UserDefaults but
    /// HomeView's in-memory copy stays stale until reloaded. Call this from
    /// surfaces that re-appear after the user could have changed settings (e.g.
    /// HomeView.onAppear, after returning from More → Settings).
    ///
    /// Toggles `settingsLoaded` around the load to suppress the `didSet`
    /// observer's save — without the guard, every reload would round-trip
    /// the just-loaded value back to UserDefaults.
    func reloadSettings() {
        settingsLoaded = false
        loadSettings()
        settingsLoaded = true
    }

    func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    // MARK: - Onboarding

    func checkOnboardingNeeded() {
        if !settings.hasCompletedOnboarding {
            showOnboarding = true
        }
    }

    func completeOnboarding(enableNutrition: Bool) {
        settings.hasCompletedOnboarding = true
        settings.isEnabled = enableNutrition
        showOnboarding = false

        if enableNutrition {
            Task {
                await healthKitService.requestReadAuthorization()
                await refreshNutrition()
            }
        }
    }

    func skipOnboarding() {
        settings.hasCompletedOnboarding = true
        settings.isEnabled = false
        showOnboarding = false
    }

    // MARK: - Data Refresh

    func refreshNutrition() async {
        guard settings.isEnabled else { return }
        isLoading = true

        if !healthKitService.isAuthorized {
            await healthKitService.requestReadAuthorization()
        }

        await healthKitService.fetchTodayNutrition()

        todayCalories = healthKitService.todayCalories
        todayProtein = healthKitService.todayProtein
        todayCarbs = healthKitService.todayCarbs
        todayFat = healthKitService.todayFat
        todayWater = healthKitService.todayWater
        sourceAppName = healthKitService.sourceAppName

        isLoading = false
    }

    // MARK: - Protein Tracking

    func logProtein(grams: Double) async {
        await healthKitService.requestWriteAuthorization()
        let success = await healthKitService.logProtein(grams: grams)
        if success {
            todayProtein += grams
        }
    }

    var proteinProgress: Double {
        guard settings.proteinTargetGrams > 0 else { return 0 }
        return min(todayProtein / settings.proteinTargetGrams, 1.0)
    }

    var proteinProgressColor: Color {
        let ratio = todayProtein / max(settings.proteinTargetGrams, 1)
        if ratio >= 0.8 { return Theme.Colors.accentGreen }
        if ratio >= 0.5 { return Color(hex: "F59E0B") } // yellow/amber
        return Theme.Colors.accentRed
    }

    // MARK: - Water Tracking

    func logWater(milliliters: Double = 250) async {
        await healthKitService.requestWriteAuthorization()
        let success = await healthKitService.logWater(milliliters: milliliters)
        if success {
            todayWater += milliliters
        }
    }

    var waterProgress: Double {
        guard settings.waterTargetML > 0 else { return 0 }
        return min(todayWater / settings.waterTargetML, 1.0)
    }

    /// Number of 250mL cups consumed
    var waterCupsConsumed: Int {
        Int(todayWater / 250)
    }

    /// Number of 250mL cups target
    var waterCupsTarget: Int {
        Int(settings.waterTargetML / 250)
    }

    // MARK: - Qualitative Labels

    var qualitativeLabel: String {
        if todayCalories == 0 && todayProtein == 0 {
            return "No nutrition data yet"
        }

        let proteinRatio = todayProtein / max(settings.proteinTargetGrams, 1)
        let waterRatio = todayWater / max(settings.waterTargetML, 1)

        if proteinRatio >= 0.8 && waterRatio >= 0.7 {
            return "Well fueled"
        } else if proteinRatio < 0.3 {
            return "Low protein"
        } else if waterRatio < 0.3 {
            return "Stay hydrated"
        } else if proteinRatio < 0.6 {
            return "Under target"
        } else {
            return "Fueling performance"
        }
    }

    var qualitativeLabelColor: Color {
        let label = qualitativeLabel
        switch label {
        case "Well fueled", "Fueling performance":
            return Theme.Colors.accentGreen
        case "Under target", "Stay hydrated":
            return Color(hex: "F59E0B")
        case "Low protein":
            return Theme.Colors.accentRed
        default:
            return Theme.Colors.textSecondary
        }
    }

    // MARK: - Delete All Data

    func deleteAllData() async {
        let success = await healthKitService.deleteAllNutritionData()
        if success {
            todayCalories = 0
            todayProtein = 0
            todayCarbs = 0
            todayFat = 0
            todayWater = 0
            sourceAppName = nil
        }
    }

    // MARK: - Display Helpers

    var shouldShowNumericValues: Bool {
        settings.displayMode != .qualitative
    }

    var shouldShowProtein: Bool {
        settings.displayMode == .proteinOnly ||
        settings.displayMode == .fullMacros ||
        settings.displayMode == .caloriesAndMacros
    }

    var shouldShowAllMacros: Bool {
        settings.displayMode == .fullMacros ||
        settings.displayMode == .caloriesAndMacros
    }

    var shouldShowCalories: Bool {
        settings.displayMode == .caloriesAndMacros
    }
}
