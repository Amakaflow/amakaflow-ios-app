//
//  NutritionViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for NutritionViewModel (AMA-1290, AMA-1291, AMA-1292).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class NutritionViewModelTests: XCTestCase {

    private var viewModel: NutritionViewModel!
    private let settingsKey = "nutrition_settings"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: settingsKey)
        let testSettings = NutritionSettings.default
        let service = NutritionHealthKitService(testing: true)
        viewModel = NutritionViewModel(settings: testSettings, healthKitService: service)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: settingsKey)
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - Default Settings Tests

    func testDefaultSettings_nutritionDisabled() {
        XCTAssertFalse(viewModel.settings.isEnabled)
    }

    func testDefaultSettings_qualitativeDisplayMode() {
        XCTAssertEqual(viewModel.settings.displayMode, .qualitative)
    }

    func testDefaultSettings_proteinTarget120g() {
        XCTAssertEqual(viewModel.settings.proteinTargetGrams, 120)
    }

    func testDefaultSettings_waterTarget2500mL() {
        XCTAssertEqual(viewModel.settings.waterTargetML, 2500)
    }

    func testDefaultSettings_onboardingNotCompleted() {
        XCTAssertFalse(viewModel.settings.hasCompletedOnboarding)
    }

    // MARK: - Onboarding Tests

    func testCheckOnboardingNeeded_showsWhenNotCompleted() {
        viewModel.checkOnboardingNeeded()
        XCTAssertTrue(viewModel.showOnboarding)
    }

    func testCheckOnboardingNeeded_doesNotShowWhenCompleted() {
        viewModel.settings.hasCompletedOnboarding = true
        viewModel.checkOnboardingNeeded()
        XCTAssertFalse(viewModel.showOnboarding)
    }

    func testCompleteOnboarding_enablesNutrition() {
        viewModel.completeOnboarding(enableNutrition: true)
        XCTAssertTrue(viewModel.settings.isEnabled)
        XCTAssertTrue(viewModel.settings.hasCompletedOnboarding)
        XCTAssertFalse(viewModel.showOnboarding)
    }

    func testCompleteOnboarding_disablesNutrition() {
        viewModel.completeOnboarding(enableNutrition: false)
        XCTAssertFalse(viewModel.settings.isEnabled)
        XCTAssertTrue(viewModel.settings.hasCompletedOnboarding)
    }

    func testSkipOnboarding_disablesAndMarksCompleted() {
        viewModel.showOnboarding = true
        viewModel.skipOnboarding()
        XCTAssertFalse(viewModel.settings.isEnabled)
        XCTAssertTrue(viewModel.settings.hasCompletedOnboarding)
        XCTAssertFalse(viewModel.showOnboarding)
    }

    // MARK: - Privacy Display Mode Tests

    func testShouldShowNumericValues_falseForQualitative() {
        viewModel.settings.displayMode = .qualitative
        XCTAssertFalse(viewModel.shouldShowNumericValues)
    }

    func testShouldShowNumericValues_trueForProteinOnly() {
        viewModel.settings.displayMode = .proteinOnly
        XCTAssertTrue(viewModel.shouldShowNumericValues)
    }

    func testShouldShowProtein_trueForProteinOnly() {
        viewModel.settings.displayMode = .proteinOnly
        XCTAssertTrue(viewModel.shouldShowProtein)
    }

    func testShouldShowProtein_falseForQualitative() {
        viewModel.settings.displayMode = .qualitative
        XCTAssertFalse(viewModel.shouldShowProtein)
    }

    func testShouldShowAllMacros_trueForFullMacros() {
        viewModel.settings.displayMode = .fullMacros
        XCTAssertTrue(viewModel.shouldShowAllMacros)
    }

    func testShouldShowAllMacros_falseForProteinOnly() {
        viewModel.settings.displayMode = .proteinOnly
        XCTAssertFalse(viewModel.shouldShowAllMacros)
    }

    func testShouldShowCalories_trueForCaloriesAndMacros() {
        viewModel.settings.displayMode = .caloriesAndMacros
        XCTAssertTrue(viewModel.shouldShowCalories)
    }

    func testShouldShowCalories_falseForFullMacros() {
        viewModel.settings.displayMode = .fullMacros
        XCTAssertFalse(viewModel.shouldShowCalories)
    }

    // MARK: - Protein Progress Tests

    func testProteinProgress_zeroWhenNoData() {
        XCTAssertEqual(viewModel.proteinProgress, 0)
    }

    func testProteinProgress_calculatesCorrectly() {
        viewModel.todayProtein = 60
        viewModel.settings.proteinTargetGrams = 120
        XCTAssertEqual(viewModel.proteinProgress, 0.5, accuracy: 0.01)
    }

    func testProteinProgress_capsAtOne() {
        viewModel.todayProtein = 200
        viewModel.settings.proteinTargetGrams = 120
        XCTAssertEqual(viewModel.proteinProgress, 1.0)
    }

    // MARK: - Water Progress Tests

    func testWaterProgress_zeroWhenNoData() {
        XCTAssertEqual(viewModel.waterProgress, 0)
    }

    func testWaterProgress_calculatesCorrectly() {
        viewModel.todayWater = 1250
        viewModel.settings.waterTargetML = 2500
        XCTAssertEqual(viewModel.waterProgress, 0.5, accuracy: 0.01)
    }

    func testWaterCupsConsumed_calculatesCorrectly() {
        viewModel.todayWater = 750
        XCTAssertEqual(viewModel.waterCupsConsumed, 3)
    }

    func testWaterCupsTarget_calculatesCorrectly() {
        viewModel.settings.waterTargetML = 2500
        XCTAssertEqual(viewModel.waterCupsTarget, 10)
    }

    // MARK: - Qualitative Label Tests

    func testQualitativeLabel_noDataYet() {
        XCTAssertEqual(viewModel.qualitativeLabel, "No nutrition data yet")
    }

    func testQualitativeLabel_wellFueled() {
        viewModel.todayCalories = 1800
        viewModel.todayProtein = 100
        viewModel.todayWater = 2000
        viewModel.settings.proteinTargetGrams = 120
        viewModel.settings.waterTargetML = 2500
        XCTAssertEqual(viewModel.qualitativeLabel, "Well fueled")
    }

    func testQualitativeLabel_lowProtein() {
        viewModel.todayCalories = 1000
        viewModel.todayProtein = 20
        viewModel.todayWater = 2000
        viewModel.settings.proteinTargetGrams = 120
        viewModel.settings.waterTargetML = 2500
        XCTAssertEqual(viewModel.qualitativeLabel, "Low protein")
    }

    func testQualitativeLabel_stayHydrated() {
        viewModel.todayCalories = 1800
        viewModel.todayProtein = 50
        viewModel.todayWater = 500
        viewModel.settings.proteinTargetGrams = 120
        viewModel.settings.waterTargetML = 2500
        XCTAssertEqual(viewModel.qualitativeLabel, "Stay hydrated")
    }

    // MARK: - Settings Persistence Tests

    func testSettingsPersistence_saveAndDecode() {
        // Modify settings
        viewModel.settings.isEnabled = true
        viewModel.settings.displayMode = .fullMacros
        viewModel.settings.proteinTargetGrams = 180
        viewModel.settings.waterTargetML = 3000
        viewModel.settings.hasCompletedOnboarding = true
        viewModel.saveSettings()

        // Read back from UserDefaults directly
        let data = UserDefaults.standard.data(forKey: settingsKey)
        XCTAssertNotNil(data, "Settings data should be persisted to UserDefaults")

        let decoded = try! JSONDecoder().decode(NutritionSettings.self, from: data!)
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.displayMode, .fullMacros)
        XCTAssertEqual(decoded.proteinTargetGrams, 180)
        XCTAssertEqual(decoded.waterTargetML, 3000)
        XCTAssertTrue(decoded.hasCompletedOnboarding)
    }

    // MARK: - Display Mode Enum Tests

    func testNutritionDisplayMode_allCasesCount() {
        XCTAssertEqual(NutritionDisplayMode.allCases.count, 4)
    }

    func testNutritionDisplayMode_titles() {
        XCTAssertEqual(NutritionDisplayMode.qualitative.title, "Qualitative only")
        XCTAssertEqual(NutritionDisplayMode.proteinOnly.title, "Protein only")
        XCTAssertEqual(NutritionDisplayMode.fullMacros.title, "Full macros")
        XCTAssertEqual(NutritionDisplayMode.caloriesAndMacros.title, "Calories + macros")
    }

    // MARK: - Settings Struct Tests

    func testNutritionSettings_codable() {
        let settings = NutritionSettings(
            isEnabled: true,
            displayMode: .proteinOnly,
            proteinTargetGrams: 150,
            waterTargetML: 3000,
            hasCompletedOnboarding: true
        )
        let data = try! JSONEncoder().encode(settings)
        let decoded = try! JSONDecoder().decode(NutritionSettings.self, from: data)
        XCTAssertEqual(settings, decoded)
    }
}
