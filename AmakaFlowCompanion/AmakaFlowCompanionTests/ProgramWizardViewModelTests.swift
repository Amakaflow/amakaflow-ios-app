//
//  ProgramWizardViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for ProgramWizardViewModel (AMA-1413 / AMA-2096)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class ProgramWizardViewModelTests: XCTestCase {

    private var viewModel: ProgramWizardViewModel!
    private var mockAPIService: MockAPIService!
    private var mockPairingService: MockPairingService!
    private var mockProgramStreamService: MockProgramStreamService!

    override func setUp() async throws {
        try await super.setUp()
        mockAPIService = MockAPIService()
        mockPairingService = MockPairingService()
        mockPairingService.storedToken = "test-token"
        mockProgramStreamService = MockProgramStreamService()
        let deps = AppDependencies(
            apiService: mockAPIService,
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService(),
            programStreamService: mockProgramStreamService
        )
        viewModel = ProgramWizardViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAPIService = nil
        mockPairingService = nil
        mockProgramStreamService = nil
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

    // MARK: - Request Contract

    func testDesignProgramRequestEncodesDocumentedSnakeCaseSchema() throws {
        configureValidWizardFields()
        viewModel.preferredDays = [1, 3, 5]

        let request = try viewModel.makeDesignProgramRequest()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["goal"] as? String, "strength")
        XCTAssertEqual(json["experience_level"] as? String, "intermediate")
        XCTAssertEqual(json["duration_weeks"] as? Int, 8)
        XCTAssertEqual(json["sessions_per_week"] as? Int, 3)
        XCTAssertEqual(json["time_per_session"] as? Int, 60)
        XCTAssertEqual(json["preferred_days"] as? [String], ["Monday", "Wednesday", "Friday"])
        XCTAssertNotNil(json["equipment"] as? [String])
        XCTAssertNil(json["experienceLevel"])
        XCTAssertNil(json["durationWeeks"])
    }

    // MARK: - Generation: Success

    func testGenerateProgramRunsDesignThenGenerateAndStopsAtReview() async {
        configureValidWizardFields()
        mockProgramStreamService.designEvents = [
            .stage(stage: "designing", message: "Designing your 8-week program...", subProgress: nil),
            .preview(previewId: "outline-preview", payload: ProgramPreviewPayload(previewId: "outline-preview", program: nil, unmatched: nil))
        ]
        mockProgramStreamService.generateEvents = [
            .stage(stage: "generating", message: "Creating Week 1 workouts...", subProgress: ProgramSubProgress(current: 1, total: 8)),
            .preview(previewId: "full-preview", payload: ProgramPreviewPayload(previewId: "full-preview", program: Self.sampleProgram, unmatched: nil))
        ]

        await viewModel.generateProgram()

        XCTAssertTrue(mockProgramStreamService.designProgramCalled)
        XCTAssertTrue(mockProgramStreamService.generateProgramCalled)
        XCTAssertEqual(mockProgramStreamService.lastGeneratePreviewId, "outline-preview")
        XCTAssertFalse(mockProgramStreamService.saveProgramCalled, "Generate must not auto-save")
        XCTAssertEqual(viewModel.designPreviewId, "outline-preview")
        XCTAssertEqual(viewModel.generatePreviewId, "full-preview")
        XCTAssertEqual(viewModel.proposedProgram?.name, "8-Week Strength Program")
        XCTAssertNil(viewModel.generatedProgramId)
        XCTAssertEqual(viewModel.currentStep, .review)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testGenerateProgramErrorEventSurfacesRealMessage() async {
        configureValidWizardFields()
        mockProgramStreamService.designEvents = [
            .error(message: "Too many active pipelines. Please wait for one to finish.", recoverable: true)
        ]

        await viewModel.generateProgram()

        XCTAssertEqual(viewModel.errorMessage, "Too many active pipelines. Please wait for one to finish.")
        XCTAssertTrue(viewModel.isErrorRecoverable)
        XCTAssertNil(viewModel.proposedProgram)
        XCTAssertFalse(viewModel.isGenerating)
    }

    // MARK: - Save

    func testSaveProgramPostsPickedDateAndSetsGeneratedProgramIdOnComplete() async throws {
        viewModel.generatePreviewId = "full-preview"
        viewModel.proposedProgram = Self.sampleProgram
        mockProgramStreamService.saveEvents = [
            .stage(stage: "saving", message: "Saving program to library...", subProgress: nil),
            .stage(stage: "scheduling", message: "Adding sessions to calendar...", subProgress: nil),
            .complete(workoutIds: ["workout-1", "workout-2"], scheduledCount: 2, workoutCount: 2)
        ]

        let startDate = try XCTUnwrap(Self.localDate(year: 2026, month: 6, day: 8))
        await viewModel.saveProgram(startDate: startDate)

        XCTAssertTrue(mockProgramStreamService.saveProgramCalled)
        XCTAssertEqual(mockProgramStreamService.lastSavePreviewId, "full-preview")
        XCTAssertEqual(mockProgramStreamService.lastScheduleStartDate, "2026-06-08")
        XCTAssertEqual(viewModel.generatedProgramId, "workout-1")
        XCTAssertEqual(viewModel.scheduledCount, 2)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Swift-6 Actor-Deinit Safety (#306)

    // Regression: deinit accessed actor-isolated streamTask, which can crash when ARC drops the
    // last reference off the MainActor executor (swift_task_deinitOnExecutorImpl). Fix: mark
    // streamTask nonisolated(unsafe). This test starts a generation stream that never completes,
    // then cancels it and releases the VM; completing without aborting proves the deinit path is safe.
    func testDeinitWithActiveStreamTaskDoesNotCrash() async throws {
        let deps = AppDependencies(
            apiService: mockAPIService,
            pairingService: mockPairingService,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService(),
            programStreamService: HangingProgramStreamService()
        )
        var local: ProgramWizardViewModel? = ProgramWizardViewModel(dependencies: deps)
        local?.equipmentPreset = "full_gym"

        let genTask = Task { @MainActor [local] in
            await local?.generateProgram()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(local?.isGenerating, true)

        genTask.cancel()
        try await Task.sleep(nanoseconds: 50_000_000)
        local = nil
    }

    // MARK: - Helpers

    private func configureValidWizardFields() {
        viewModel.goal = "strength"
        viewModel.experienceLevel = "intermediate"
        viewModel.durationWeeks = 8
        viewModel.sessionsPerWeek = 3
        viewModel.timePerSession = 60
        viewModel.equipmentPreset = "full_gym"
    }

    private static var sampleProgram: ProposedProgram {
        ProposedProgram(
            id: nil,
            name: "8-Week Strength Program",
            goal: "strength",
            durationWeeks: 8,
            sessionsPerWeek: 3,
            periodizationModel: "linear",
            weeks: [
                ProposedProgramWeek(
                    weekNumber: 1,
                    focus: "Base strength",
                    intensityPercentage: 70,
                    volumeModifier: 1.0,
                    isDeload: false,
                    workouts: [
                        ProposedProgramWorkout(
                            name: "Lower Strength",
                            dayOfWeek: 0,
                            workoutType: "strength",
                            targetDurationMinutes: 60,
                            exercises: [
                                ProposedProgramExercise(name: "Back Squat", sets: 4, reps: "5", restSeconds: 180, notes: nil, tempo: nil, rpe: 8)
                            ]
                        )
                    ]
                )
            ]
        )
    }

    private static func localDate(year: Int, month: Int, day: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    private final class HangingProgramStreamService: ProgramStreamProviding {
        func designProgram(request: DesignProgramRequest, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in }
            }
        }
        func generateProgram(previewId: String, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in
                    continuation.finish(throwing: CancellationError())
                }
            }
        }
        func saveProgram(previewId: String, scheduleStartDate: String?, token: String) -> AsyncThrowingStream<ProgramStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in
                    continuation.finish(throwing: CancellationError())
                }
            }
        }
    }
}
