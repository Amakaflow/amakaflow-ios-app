//
//  ProgramWizardViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for ProgramWizardViewModel (AMA-1413)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ProgramWizardViewModelTests: XCTestCase {

    private var viewModel: ProgramWizardViewModel!
    private var mockAPIService: MockAPIService!

    override func setUp() async throws {
        try await super.setUp()
        mockAPIService = MockAPIService()
        let deps = AppDependencies(
            apiService: mockAPIService,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        viewModel = ProgramWizardViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPIService = nil
        try await super.tearDown()
    }

    // MARK: - canAdvance: Goal Step

    func testCanAdvanceGoalStep_nilGoalReturnsFalse() {
        viewModel.currentStep = .goal
        viewModel.goal = nil
        XCTAssertFalse(viewModel.canAdvance)
    }

    func testCanAdvanceGoalStep_setGoalReturnsTrue() {
        viewModel.currentStep = .goal
        viewModel.goal = "strength"
        XCTAssertTrue(viewModel.canAdvance)
    }

    // MARK: - canAdvance: Schedule Step

    func testCanAdvanceScheduleStep_emptyPreferredDaysReturnsFalse() {
        viewModel.currentStep = .schedule
        viewModel.preferredDays = []
        XCTAssertFalse(viewModel.canAdvance)
    }

    func testCanAdvanceScheduleStep_withDaysReturnsTrue() {
        viewModel.currentStep = .schedule
        viewModel.preferredDays = [1, 3, 5]
        XCTAssertTrue(viewModel.canAdvance)
    }

    // MARK: - canAdvance: Equipment Step

    func testCanAdvanceEquipmentStep_noPresetAndNoCustomReturnsFalse() {
        viewModel.currentStep = .equipment
        viewModel.equipmentPreset = nil
        viewModel.customEquipment = []
        viewModel.useCustomEquipment = false
        XCTAssertFalse(viewModel.canAdvance)
    }

    func testCanAdvanceEquipmentStep_withPresetReturnsTrue() {
        viewModel.currentStep = .equipment
        viewModel.equipmentPreset = "full_gym"
        viewModel.useCustomEquipment = false
        XCTAssertTrue(viewModel.canAdvance)
    }

    func testCanAdvanceEquipmentStep_withCustomItemsReturnsTrue() {
        viewModel.currentStep = .equipment
        viewModel.equipmentPreset = nil
        viewModel.useCustomEquipment = true
        viewModel.customEquipment = ["dumbbells"]
        XCTAssertTrue(viewModel.canAdvance)
    }

    // MARK: - Navigation

    func testNextStep_advancesFromGoalToExperience() {
        viewModel.currentStep = .goal
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .experience)
    }

    func testNextStep_doesNotAdvancePastReview() {
        viewModel.currentStep = .review
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .review)
    }

    func testPreviousStep_goesBackFromExperienceToGoal() {
        viewModel.currentStep = .experience
        viewModel.previousStep()
        XCTAssertEqual(viewModel.currentStep, .goal)
    }

    func testPreviousStep_doesNotGoBackPastGoal() {
        viewModel.currentStep = .goal
        viewModel.previousStep()
        XCTAssertEqual(viewModel.currentStep, .goal)
    }

    // MARK: - Equipment Resolution

    func testResolvedEquipmentPreset_returnsPresetItems() {
        viewModel.useCustomEquipment = false
        viewModel.equipmentPreset = "bodyweight"
        let resolved = viewModel.resolvedEquipment
        XCTAssertEqual(resolved.sorted(), ["pull-up bar", "resistance bands"].sorted())
    }

    func testResolvedEquipmentCustom_returnsCustomItems() {
        viewModel.useCustomEquipment = true
        viewModel.customEquipment = ["dumbbells", "bench"]
        let resolved = viewModel.resolvedEquipment
        XCTAssertEqual(resolved.sorted(), ["bench", "dumbbells"])
    }

    func testResolvedEquipmentCustomOverridesPreset() {
        viewModel.useCustomEquipment = true
        viewModel.equipmentPreset = "full_gym"
        viewModel.customEquipment = ["dumbbells"]
        let resolved = viewModel.resolvedEquipment
        XCTAssertEqual(resolved, ["dumbbells"])
    }

    // MARK: - Generation: Success

    func testGenerateProgramSuccess_setsGeneratedProgramId() async {
        // Configure mock: start job then immediately complete
        mockAPIService.generateProgramResult = .success(
            ProgramGenerationResponse(jobId: "job-001", status: "queued", programId: nil, error: nil)
        )
        mockAPIService.fetchGenerationStatusResult = .success(
            ProgramGenerationStatus(jobId: "job-001", status: "completed", progress: 100, programId: "prog-abc", error: nil)
        )

        viewModel.goal = "strength"
        viewModel.experienceLevel = "intermediate"
        viewModel.equipmentPreset = "full_gym"

        await viewModel.generateProgram()

        XCTAssertTrue(mockAPIService.generateProgramCalled)
        XCTAssertEqual(viewModel.generatedProgramId, "prog-abc")
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Generation: Error on start

    func testGenerateProgramError_setsErrorMessage() async {
        mockAPIService.generateProgramResult = .failure(APIError.serverError(500))

        await viewModel.generateProgram()

        XCTAssertTrue(mockAPIService.generateProgramCalled)
        XCTAssertNil(viewModel.generatedProgramId)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Generation: Failed status from poll

    func testGenerateProgramFailedStatus_setsErrorMessage() async {
        mockAPIService.generateProgramResult = .success(
            ProgramGenerationResponse(jobId: "job-002", status: "queued", programId: nil, error: nil)
        )
        mockAPIService.fetchGenerationStatusResult = .success(
            ProgramGenerationStatus(jobId: "job-002", status: "failed", progress: 0, programId: nil, error: "AI overloaded")
        )

        await viewModel.generateProgram()

        XCTAssertNil(viewModel.generatedProgramId)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertEqual(viewModel.errorMessage, "AI overloaded")
    }
}
