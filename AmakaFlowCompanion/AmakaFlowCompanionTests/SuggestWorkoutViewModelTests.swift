//
//  SuggestWorkoutViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for the SuggestWorkoutViewModel (AMA-1265).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class SuggestWorkoutViewModelTests: XCTestCase {

    private var viewModel: SuggestWorkoutViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = SuggestWorkoutViewModel()
        // Clear any stored coaching profile
        UserDefaults.standard.removeObject(forKey: "coaching_profile")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "coaching_profile")
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - Profile Tests

    func testHasCoachingProfile_returnsFalseWhenNoProfile() {
        XCTAssertFalse(viewModel.hasCoachingProfile)
    }

    func testHasCoachingProfile_returnsTrueAfterSave() {
        let profile = CoachingProfile(
            experience: .intermediate,
            goal: .buildMuscle,
            daysPerWeek: 4
        )
        viewModel.saveProfile(profile)
        XCTAssertTrue(viewModel.hasCoachingProfile)
    }

    func testLoadProfile_returnsNilWhenNoProfile() {
        XCTAssertNil(viewModel.loadProfile())
    }

    func testLoadProfile_returnsStoredProfile() {
        let profile = CoachingProfile(
            experience: .advanced,
            goal: .athletic,
            daysPerWeek: 6
        )
        viewModel.saveProfile(profile)

        let loaded = viewModel.loadProfile()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.experience, .advanced)
        XCTAssertEqual(loaded?.goal, .athletic)
        XCTAssertEqual(loaded?.daysPerWeek, 6)
    }

    // MARK: - State Tests

    func testInitialState_isIdle() {
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testRequestSuggestion_showsOnboardingWhenNoProfile() {
        viewModel.requestSuggestion()
        XCTAssertEqual(viewModel.state, .needsOnboarding)
    }

    func testRequestSuggestion_startsLoadingWhenProfileExists() async throws {
        // Save a profile first
        let profile = CoachingProfile(
            experience: .beginner,
            goal: .generalFitness,
            daysPerWeek: 3
        )
        viewModel.saveProfile(profile)

        viewModel.requestSuggestion()

        // Should transition to loading (the API call will fail in tests, which is fine)
        // Give a brief moment for the Task to kick off
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // State should be loading or error (since no real API is running)
        let state = viewModel.state
        switch state {
        case .loading, .error:
            // Expected - either still loading or errored out from missing API
            break
        default:
            XCTFail("Expected loading or error state, got \(state)")
        }
    }

    func testCompleteOnboarding_savesProfileAndStartsLoading() async throws {
        viewModel.completeOnboarding(
            experience: .intermediate,
            goal: .buildMuscle,
            daysPerWeek: 4
        )

        // Profile should be saved
        XCTAssertTrue(viewModel.hasCoachingProfile)
        let loaded = viewModel.loadProfile()
        XCTAssertEqual(loaded?.experience, .intermediate)
        XCTAssertEqual(loaded?.goal, .buildMuscle)
        XCTAssertEqual(loaded?.daysPerWeek, 4)

        // Should transition to loading
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        let state = viewModel.state
        switch state {
        case .loading, .error:
            break
        default:
            XCTFail("Expected loading or error state, got \(state)")
        }
    }

    func testReset_clearsState() {
        viewModel.state = .error("test error")
        viewModel.suggestedWorkout = Workout(
            name: "Test",
            sport: .strength,
            duration: 1800,
            intervals: [],
            source: .coach
        )

        viewModel.reset()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.suggestedWorkout)
    }

    // MARK: - Model Tests

    func testExperienceLevel_displayNames() {
        XCTAssertEqual(ExperienceLevel.beginner.displayName, "Beginner")
        XCTAssertEqual(ExperienceLevel.intermediate.displayName, "Intermediate")
        XCTAssertEqual(ExperienceLevel.advanced.displayName, "Advanced")
    }

    func testTrainingGoal_displayNames() {
        XCTAssertEqual(TrainingGoal.loseWeight.displayName, "Lose Weight")
        XCTAssertEqual(TrainingGoal.buildMuscle.displayName, "Build Muscle")
        XCTAssertEqual(TrainingGoal.improveEndurance.displayName, "Improve Endurance")
        XCTAssertEqual(TrainingGoal.generalFitness.displayName, "General Fitness")
        XCTAssertEqual(TrainingGoal.athletic.displayName, "Athletic Performance")
    }

    func testSuggestWorkoutState_equality() {
        XCTAssertEqual(SuggestWorkoutState.idle, SuggestWorkoutState.idle)
        XCTAssertEqual(SuggestWorkoutState.loading, SuggestWorkoutState.loading)
        XCTAssertEqual(SuggestWorkoutState.needsOnboarding, SuggestWorkoutState.needsOnboarding)
        XCTAssertEqual(SuggestWorkoutState.error("a"), SuggestWorkoutState.error("a"))
        XCTAssertNotEqual(SuggestWorkoutState.error("a"), SuggestWorkoutState.error("b"))
        XCTAssertNotEqual(SuggestWorkoutState.idle, SuggestWorkoutState.loading)
    }
}
