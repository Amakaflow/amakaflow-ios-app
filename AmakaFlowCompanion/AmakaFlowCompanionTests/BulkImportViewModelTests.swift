//
//  BulkImportViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for BulkImportViewModel (AMA-1415)
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class BulkImportViewModelTests: XCTestCase {

    private var mockAPI: MockAPIService!
    private var mockPairing: MockPairingService!
    private var sut: BulkImportViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockAPI = await MockAPIService()
        mockPairing = await MockPairingService()
        // Provide a stub profile so auth guard passes in all wizard steps
        mockPairing.userProfile = UserProfile(id: "test-profile-001", email: "test@example.com", name: "Test User", avatarUrl: nil)
        let deps = await AppDependencies(
            apiService: mockAPI,
            pairingService: mockPairing,
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        sut = BulkImportViewModel(dependencies: deps)
    }

    override func tearDown() async throws {
        sut = nil
        mockAPI = nil
        mockPairing = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeDetectResponse(jobId: String = "job-001", itemCount: Int = 2) -> BulkDetectResponse {
        let items = (0..<itemCount).map { idx in
            DetectedItem(
                id: "item-\(idx)",
                sourceRef: "https://example.com/\(idx)",
                parsedTitle: "Workout \(idx)",
                parsedExerciseCount: 6,
                confidence: 85,
                errors: nil,
                warnings: nil
            )
        }
        return BulkDetectResponse(
            success: true,
            jobId: jobId,
            items: items,
            total: itemCount,
            successCount: itemCount,
            errorCount: 0
        )
    }

    private func makeMatchResponse(jobId: String = "job-001") -> BulkMatchResponse {
        BulkMatchResponse(
            success: true,
            jobId: jobId,
            exercises: [
                ExerciseMatch(
                    id: "ex-001",
                    originalName: "Bench Press",
                    matchedGarminName: "Bench Press",
                    confidence: 95,
                    suggestions: nil,
                    status: "matched",
                    userSelection: nil
                ),
                ExerciseMatch(
                    id: "ex-002",
                    originalName: "Pullup",
                    matchedGarminName: nil,
                    confidence: 60,
                    suggestions: [ExerciseSuggestion(name: "Pull Up", confidence: 80)],
                    status: "needs_review",
                    userSelection: nil
                )
            ],
            totalExercises: 2,
            matched: 1,
            needsReview: 1
        )
    }

    private func makePreviewResponse(jobId: String = "job-001") -> BulkPreviewResponse {
        BulkPreviewResponse(
            success: true,
            jobId: jobId,
            workouts: [
                PreviewWorkout(
                    id: "pw-001",
                    title: "Push Day A",
                    exerciseCount: 6,
                    blockCount: 2,
                    validationIssues: nil,
                    selected: true,
                    isDuplicate: false
                ),
                PreviewWorkout(
                    id: "pw-002",
                    title: "Pull Day B",
                    exerciseCount: 5,
                    blockCount: nil,
                    validationIssues: nil,
                    selected: true,
                    isDuplicate: false
                )
            ],
            stats: ImportStats(
                totalDetected: 2,
                totalSelected: 2,
                exercisesMatched: 1,
                exercisesNeedingReview: 1,
                duplicatesFound: 0,
                validationErrors: 0,
                validationWarnings: 0
            )
        )
    }

    private func makeExecuteResponse(jobId: String = "job-001") -> BulkExecuteResponse {
        BulkExecuteResponse(success: true, jobId: jobId, status: "running", message: "Import started")
    }

    private func makeCompleteStatus(jobId: String = "job-001") -> BulkImportStatus {
        BulkImportStatus(
            success: true,
            jobId: jobId,
            status: "complete",
            progress: 100,
            results: [
                ImportResult(workoutId: "pw-001", title: "Push Day A", status: "success", error: nil, savedWorkoutId: "saved-001"),
                ImportResult(workoutId: "pw-002", title: "Pull Day B", status: "success", error: nil, savedWorkoutId: "saved-002")
            ],
            error: nil
        )
    }

    // MARK: - testDetect

    func testDetect_populatesDetectedItems() async {
        sut.urlInputs = ["https://example.com/workout1", "https://example.com/workout2"]
        mockAPI.detectImportResult = .success(makeDetectResponse(itemCount: 2))

        await sut.detect()

        XCTAssertEqual(sut.detectedItems.count, 2, "Should have 2 detected items")
        XCTAssertEqual(sut.jobId, "job-001")
        XCTAssertEqual(sut.currentStep, .detect)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(mockAPI.detectImportCalled)
    }

    func testDetect_withEmptyURLs_setsErrorMessage() async {
        sut.urlInputs = ["", "  "]

        await sut.detect()

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(sut.currentStep, .source, "Should stay on source step")
        XCTAssertFalse(mockAPI.detectImportCalled)
    }

    // MARK: - testMatchExercises

    func testMatchExercises_populatesExerciseMatches() async {
        // Set up precondition: job exists from detect
        sut.urlInputs = ["https://example.com/w1"]
        mockAPI.detectImportResult = .success(makeDetectResponse())
        await sut.detect()

        mockAPI.matchExercisesResult = .success(makeMatchResponse())

        await sut.matchExercises()

        XCTAssertEqual(sut.exerciseMatches.count, 2)
        XCTAssertEqual(sut.matchStats?.matched, 1)
        XCTAssertEqual(sut.matchStats?.needsReview, 1)
        XCTAssertEqual(sut.matchStats?.total, 2)
        XCTAssertEqual(sut.currentStep, .match)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(mockAPI.matchExercisesCalled)
    }

    // MARK: - testPreview

    func testPreview_populatesPreviewWorkouts() async {
        // Set up jobId via detect
        sut.urlInputs = ["https://example.com/w1"]
        mockAPI.detectImportResult = .success(makeDetectResponse())
        await sut.detect()

        mockAPI.previewImportResult = .success(makePreviewResponse())

        await sut.preview()

        XCTAssertEqual(sut.previewWorkouts.count, 2)
        XCTAssertNotNil(sut.importStats)
        XCTAssertEqual(sut.importStats?.totalDetected, 2)
        XCTAssertEqual(sut.currentStep, .preview)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(mockAPI.previewImportCalled)
    }

    // MARK: - testToggleWorkoutSelection

    func testToggleWorkoutSelection_togglesCorrectItem() async {
        // Load preview workouts
        sut.urlInputs = ["https://example.com/w1"]
        mockAPI.detectImportResult = .success(makeDetectResponse())
        await sut.detect()

        mockAPI.previewImportResult = .success(makePreviewResponse())
        await sut.preview()

        // Initially both selected
        XCTAssertTrue(sut.previewWorkouts[0].selected)

        // Toggle first item off
        sut.toggleWorkoutSelection("pw-001")
        XCTAssertFalse(sut.previewWorkouts[0].selected)

        // Toggle first item back on
        sut.toggleWorkoutSelection("pw-001")
        XCTAssertTrue(sut.previewWorkouts[0].selected)
    }

    // MARK: - testUpdateExerciseMapping

    func testUpdateExerciseMapping_updatesUserSelection() async {
        sut.urlInputs = ["https://example.com/w1"]
        mockAPI.detectImportResult = .success(makeDetectResponse())
        await sut.detect()

        mockAPI.matchExercisesResult = .success(makeMatchResponse())
        await sut.matchExercises()

        // ex-002 has no selection initially
        let beforeUpdate = sut.exerciseMatches.first { $0.id == "ex-002" }
        XCTAssertNil(beforeUpdate?.userSelection)

        sut.updateExerciseMapping(exerciseId: "ex-002", garminName: "Pull Up")

        let afterUpdate = sut.exerciseMatches.first { $0.id == "ex-002" }
        XCTAssertEqual(afterUpdate?.userSelection, "Pull Up")
    }

    // MARK: - testExecuteImportSuccess

    func testExecuteImportSuccess_setsImportComplete() async {
        // Set up through all steps
        sut.urlInputs = ["https://example.com/w1"]
        mockAPI.detectImportResult = .success(makeDetectResponse())
        await sut.detect()

        mockAPI.matchExercisesResult = .success(makeMatchResponse())
        await sut.matchExercises()

        mockAPI.previewImportResult = .success(makePreviewResponse())
        await sut.preview()

        // Execute returns running, then status returns complete immediately
        mockAPI.executeImportResult = .success(makeExecuteResponse())
        mockAPI.fetchImportStatusResult = .success(makeCompleteStatus())

        await sut.executeImport()

        // Poll until importComplete or timeout (up to 2s in 50ms increments)
        var waited = 0
        while !sut.importComplete && waited < 40 {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            waited += 1
        }

        XCTAssertTrue(sut.importComplete)
        XCTAssertEqual(sut.importProgress, 100)
        XCTAssertEqual(sut.importResults.count, 2)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - testDetectError

    func testDetectError_setsErrorMessage() async {
        sut.urlInputs = ["https://example.com/w1"]
        mockAPI.detectImportResult = .failure(APIError.serverError(500))

        await sut.detect()

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(sut.currentStep, .source, "Should stay on source step on error")
        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(sut.detectedItems.isEmpty)
    }

    // MARK: - URL Management

    func testAddURL_appendsEmptyEntry() {
        XCTAssertEqual(sut.urlInputs.count, 1)
        sut.addURL()
        XCTAssertEqual(sut.urlInputs.count, 2)
        XCTAssertEqual(sut.urlInputs.last, "")
    }

    func testRemoveURL_removesCorrectIndex() {
        sut.urlInputs = ["https://a.com", "https://b.com", "https://c.com"]
        sut.removeURL(at: 1)
        XCTAssertEqual(sut.urlInputs, ["https://a.com", "https://c.com"])
    }

    func testRemoveURL_doesNotRemoveLastItem() {
        sut.urlInputs = ["https://only.com"]
        sut.removeURL(at: 0)
        XCTAssertEqual(sut.urlInputs.count, 1, "Should not remove the last URL field")
    }
}
