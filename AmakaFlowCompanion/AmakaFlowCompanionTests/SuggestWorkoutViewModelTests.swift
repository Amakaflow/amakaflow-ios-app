//
//  SuggestWorkoutViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for the SuggestWorkoutViewModel (AMA-1265, AMA-1730).
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class SuggestWorkoutViewModelTests: XCTestCase {

  private var mockAPI: MockAPIService!
  private var viewModel: SuggestWorkoutViewModel!

  override func setUp() async throws {
    try await super.setUp()
    UserDefaults.standard.removeObject(forKey: "coaching_profile")
    mockAPI = MockAPIService()
    viewModel = SuggestWorkoutViewModel(dependencies: makeDependencies(apiService: mockAPI))
  }

  override func tearDown() async throws {
    UserDefaults.standard.removeObject(forKey: "coaching_profile")
    viewModel = nil
    mockAPI = nil
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
    XCTAssertNil(viewModel.suggestedWorkout)
  }

  func testRequestSuggestion_showsOnboardingWhenNoBackendProfile() async throws {
    mockAPI.getCoachingProfileResult = .success(nil)

    viewModel.requestSuggestion()
    try await waitUntil { self.viewModel.state == .needsOnboarding }

    XCTAssertTrue(mockAPI.getCoachingProfileCalled)
    XCTAssertEqual(viewModel.state, .needsOnboarding)
    XCTAssertNil(viewModel.ctaError)
    XCTAssertFalse(mockAPI.suggestWorkoutCalled)
  }

  func testRequestSuggestion_profileLoadErrorStaysLoud() async throws {
    mockAPI.getCoachingProfileResult = .failure(APIError.serverError(500))

    viewModel.requestSuggestion()
    try await waitUntil {
      if case .error = self.viewModel.state { return true }
      return false
    }

    XCTAssertTrue(mockAPI.getCoachingProfileCalled)
    XCTAssertFalse(mockAPI.suggestWorkoutCalled)
    guard case .error(let cta) = viewModel.state else {
      return XCTFail("Expected error state, got \(viewModel.state)")
    }
    guard case .http(let status, _, _) = cta else {
      return XCTFail("Expected HTTP CTAError, got \(cta)")
    }
    XCTAssertEqual(status, 500)
  }

  func testSuggestWorkout_setsLoadingWhileRequestIsPending() async throws {
    let delayedAPI = DelayedSuggestWorkoutAPIService(
      response: .single(kind: .time(seconds: 120, target: "easy spin"))
    )
    viewModel = SuggestWorkoutViewModel(dependencies: makeDependencies(apiService: delayedAPI))

    let task = Task { await viewModel.suggestWorkout() }
    try await waitUntil { self.viewModel.state == .loading }

    XCTAssertEqual(viewModel.state, .loading)
    delayedAPI.resume()
    await task.value
  }

  func testSuggestWorkout_successBuildsWorkoutAndStoresSuggestion() async {
    mockAPI.getFatigueAdviceResult = .success(
      FatigueAdvice(
        level: .low,
        message: "You’re recovered",
        recommendations: [],
        suggestedRestDays: nil,
        recoveryActivities: nil
      )
    )
    mockAPI.suggestWorkoutResult = .success(.single(kind: .time(seconds: 300, target: "zone 2")))

    await viewModel.suggestWorkout(durationMinutes: 30, focusMuscleGroups: ["quads"], notes: "easy")

    XCTAssertTrue(mockAPI.getFatigueAdviceCalled)
    XCTAssertEqual(viewModel.readinessLevel, .green)
    XCTAssertEqual(viewModel.readinessMessage, "You’re recovered")
    XCTAssertTrue(mockAPI.suggestWorkoutCalled)
    XCTAssertEqual(mockAPI.lastSuggestWorkoutRequest?.durationMinutes, 30)
    XCTAssertEqual(mockAPI.lastSuggestWorkoutRequest?.focusMuscleGroups, ["quads"])
    XCTAssertEqual(mockAPI.lastSuggestWorkoutRequest?.notes, "easy")
    XCTAssertEqual(viewModel.suggestedWorkout?.name, "AI Suggested Workout")
    XCTAssertEqual(viewModel.suggestedWorkout?.sport, .strength)
    XCTAssertEqual(viewModel.suggestedWorkout?.duration, 300)
    XCTAssertEqual(viewModel.suggestedWorkout?.source, .coach)
    guard case .success(let workout) = viewModel.state else {
      XCTFail("Expected success state, got \(viewModel.state)")
      return
    }
    XCTAssertEqual(workout.intervals, [.time(seconds: 300, target: "zone 2")])
  }

  func testSuggestWorkout_emptyResponseSetsEmptyStateAndNoSuggestion() async {
    mockAPI.suggestWorkoutResult = .success(
      SuggestWorkoutResponse(
        blocks: [],
        warmUp: nil,
        cooldown: nil,
        name: nil,
        sport: nil,
        durationSeconds: nil,
        description: nil
      )
    )

    await viewModel.suggestWorkout()

    XCTAssertTrue(mockAPI.suggestWorkoutCalled)
    XCTAssertNil(viewModel.suggestedWorkout)
    XCTAssertEqual(viewModel.state, .empty)
  }

  func testSuggestWorkout_readinessMappingsAreLevelOnly() async {
    mockAPI.getFatigueAdviceResult = .success(
      FatigueAdvice(
        level: .critical,
        message: "Keep this easy",
        recommendations: ["Rest"],
        suggestedRestDays: 1,
        recoveryActivities: nil
      )
    )
    mockAPI.suggestWorkoutResult = .success(.single(kind: .time(seconds: 180, target: "walk")))

    await viewModel.suggestWorkout()

    XCTAssertEqual(viewModel.readinessLevel, .red)
    XCTAssertEqual(viewModel.readinessMessage, "Keep this easy")
  }

  func testSuggestWorkout_readinessFailureIsUnknownButDoesNotFabricateMetrics() async {
    mockAPI.getFatigueAdviceResult = .failure(APIError.serverError(503))
    mockAPI.suggestWorkoutResult = .success(.single(kind: .time(seconds: 180, target: "walk")))

    await viewModel.suggestWorkout()

    XCTAssertEqual(viewModel.readinessLevel, .unknown)
    XCTAssertNil(viewModel.readinessMessage)
    guard case .success = viewModel.state else {
      return XCTFail("Expected success with unknown readiness, got \(viewModel.state)")
    }
  }

  func testSuggestWorkout_errorSetsErrorStateAndLeavesSuggestionNil() async {
    mockAPI.suggestWorkoutResult = .failure(APIError.serverError(500))

    await viewModel.suggestWorkout()

    XCTAssertTrue(mockAPI.suggestWorkoutCalled)
    XCTAssertNil(viewModel.suggestedWorkout)
    guard case .error(let cta) = viewModel.state else {
      XCTFail("Expected error state, got \(viewModel.state)")
      return
    }
    // AMA-1803 P1: state.error now carries a typed CTAError. The
    // userMessage must be non-empty so the View has something to show.
    XCTAssertFalse(cta.userMessage.isEmpty)
  }

  func testSuggestWorkout_422SetsNonRetryableCTAErrorAndLeavesSuggestionNil() async {
    mockAPI.suggestWorkoutResult = .failure(APIError.serverError(422))

    await viewModel.suggestWorkout()

    XCTAssertTrue(mockAPI.suggestWorkoutCalled)
    XCTAssertNil(viewModel.suggestedWorkout)
    guard case .error(let cta) = viewModel.state else {
      return XCTFail("Expected error state, got \(viewModel.state)")
    }
    guard case .http(let status, _, _) = cta else {
      return XCTFail("Expected .http CTAError, got \(cta)")
    }
    XCTAssertEqual(status, 422)
    XCTAssertFalse(cta.isRetryable, "4xx validation failures must not offer Retry")
  }

  func testSuggestWorkout_directURLErrorSetsRetryableCTAErrorAndLeavesSuggestionNil() async {
    mockAPI.suggestWorkoutResult = .failure(URLError(.notConnectedToInternet))

    await viewModel.suggestWorkout()

    XCTAssertTrue(mockAPI.suggestWorkoutCalled)
    XCTAssertNil(viewModel.suggestedWorkout)
    guard case .error(let cta) = viewModel.state else {
      return XCTFail("Expected error state, got \(viewModel.state)")
    }
    guard case .network(let code, _) = cta else {
      return XCTFail("Expected .network CTAError, got \(cta)")
    }
    XCTAssertEqual(code, .notConnectedToInternet)
    XCTAssertTrue(cta.isRetryable, "offline transport failures must offer Retry")
  }

  func testCompleteOnboarding_savesProfileAndRequestsSuggestion() async throws {
    mockAPI.suggestWorkoutResult = .success(.single(kind: .rest(seconds: 60)))

    viewModel.completeOnboarding(
      experience: .intermediate,
      goal: .buildMuscle,
      daysPerWeek: 4
    )

    try await waitUntil { self.mockAPI.suggestWorkoutCalled }
    XCTAssertTrue(viewModel.hasCoachingProfile)
    XCTAssertEqual(viewModel.loadProfile()?.experience, .intermediate)
    XCTAssertEqual(viewModel.loadProfile()?.goal, .buildMuscle)
    XCTAssertEqual(viewModel.loadProfile()?.daysPerWeek, 4)
    guard case .success = viewModel.state else {
      XCTFail("Expected success state, got \(viewModel.state)")
      return
    }
  }

  func testSuggestAnotherReRequestsFreshSuggestionWithVariationNote() async {
    mockAPI.suggestWorkoutResult = .success(.single(kind: .time(seconds: 300, target: "zone 2")))

    await viewModel.suggestWorkout()
    await viewModel.suggestAnother()

    XCTAssertEqual(mockAPI.suggestWorkoutCallCount, 2)
    XCTAssertEqual(
      mockAPI.lastSuggestWorkoutRequest?.notes,
      "Suggest a different session than the previous suggestion."
    )
    guard case .success = viewModel.state else {
      return XCTFail("Expected success after swap re-request, got \(viewModel.state)")
    }
  }

  func testRestTodayMarksRestAndClearsSuggestion() {
    viewModel.suggestedWorkout = Workout(
      name: "Test",
      sport: .strength,
      duration: 1800,
      intervals: [.time(seconds: 60, target: "move")],
      source: .coach
    )
    viewModel.state = .success(viewModel.suggestedWorkout!)

    viewModel.restToday()

    XCTAssertTrue(viewModel.didChooseRestToday)
    XCTAssertEqual(viewModel.state, .idle)
    XCTAssertNil(viewModel.suggestedWorkout)
  }

  func testReset_clearsState() {
    viewModel.state = .error(.unknown(description: "test error"))
    viewModel.ctaError = .unknown(description: "test error")
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
    XCTAssertNil(viewModel.ctaError)
  }

  // MARK: - buildWorkout(from:) Translation Tests

  func testBuildWorkout_includesWarmupBeforeBlocksAndCooldownAfterBlocks() async throws {
    let response = SuggestWorkoutResponse(
      blocks: [.time(seconds: 180, target: "tempo")],
      warmUp: WarmUpCooldown(seconds: 300, target: "ramp"),
      cooldown: WarmUpCooldown(seconds: 120, target: "walk"),
      name: "Tempo Run",
      sport: .running,
      durationSeconds: 600,
      description: "Controlled effort"
    )

    let workout = try await buildWorkout(response)

    XCTAssertEqual(workout.name, "Tempo Run")
    XCTAssertEqual(workout.sport, .running)
    XCTAssertEqual(workout.duration, 600)
    XCTAssertEqual(workout.description, "Controlled effort")
    XCTAssertEqual(
      workout.intervals,
      [
        .warmup(seconds: 300, target: "ramp"),
        .time(seconds: 180, target: "tempo"),
        .cooldown(seconds: 120, target: "walk"),
      ]
    )
  }

  func testBuildWorkout_translatesWarmupIntervalKind() async throws {
    let workout = try await buildWorkout(.single(kind: .warmup(seconds: 90, target: "hips")))
    XCTAssertEqual(workout.intervals, [.warmup(seconds: 90, target: "hips")])
    XCTAssertEqual(workout.duration, 90)
  }

  func testBuildWorkout_translatesCooldownIntervalKind() async throws {
    let workout = try await buildWorkout(.single(kind: .cooldown(seconds: 80, target: "breathe")))
    XCTAssertEqual(workout.intervals, [.cooldown(seconds: 80, target: "breathe")])
    XCTAssertEqual(workout.duration, 80)
  }

  func testBuildWorkout_translatesTimeIntervalKind() async throws {
    let workout = try await buildWorkout(.single(kind: .time(seconds: 240, target: "steady")))
    XCTAssertEqual(workout.intervals, [.time(seconds: 240, target: "steady")])
    XCTAssertEqual(workout.duration, 240)
  }

  func testBuildWorkout_translatesRepsIntervalKindAndPreservesLoadAndReps() async throws {
    let workout = try await buildWorkout(
      .single(
        kind: .reps(
          sets: 4,
          reps: 8,
          name: "bench press",
          load: "82.5 kg",
          restSec: 120,
          followAlongUrl: "https://example.com/bench"
        )
      )
    )

    XCTAssertEqual(workout.duration, 120)
    assertReps(
      workout.intervals.first,
      sets: 4,
      reps: 8,
      name: "bench press",
      load: "82.5kg",
      restSec: 120,
      followAlongUrl: nil
    )
  }

  func testBuildWorkout_translatesDistanceIntervalKind() async throws {
    let workout = try await buildWorkout(.single(kind: .distance(meters: 1_000, target: "5k pace")))
    XCTAssertEqual(workout.intervals, [.distance(meters: 1_000, target: "5k pace")])
    XCTAssertEqual(workout.duration, 60)
  }

  func testBuildWorkout_translatesRepeatIntervalKind() async throws {
    let repeatInterval = WorkoutInterval.repeat(
      reps: 3,
      intervals: [
        .time(seconds: 45, target: "hard"),
        .rest(seconds: 30),
      ]
    )

    let workout = try await buildWorkout(.single(kind: repeatInterval))

    XCTAssertEqual(
      workout.intervals,
      [
        .repeat(
          reps: 3,
          intervals: [.time(seconds: 45, target: "hard")]
        )
      ]
    )
    XCTAssertEqual(workout.duration, 60)
  }

  func testBuildWorkout_translatesRestIntervalKind() async throws {
    let workout = try await buildWorkout(.single(kind: .rest(seconds: 75)))
    XCTAssertEqual(workout.intervals, [])
    XCTAssertEqual(workout.duration, 75)
  }

  func testBuildWorkout_handlesEveryOptionalNilBackendShape() async throws {
    let response = SuggestWorkoutResponse(
      blocks: [.rest(seconds: nil)],
      warmUp: nil,
      cooldown: nil,
      name: nil,
      sport: nil,
      durationSeconds: nil,
      description: nil
    )

    let workout = try await buildWorkout(response)

    XCTAssertEqual(workout.name, "AI Suggested Workout")
    XCTAssertEqual(workout.sport, .strength)
    XCTAssertEqual(workout.duration, 60)
    XCTAssertNil(workout.description)
    XCTAssertEqual(workout.intervals, [])
  }

  func testBuildWorkout_snapshotForCanonicalAMA1720SuggestedWorkoutPayload() async throws {
    let workout = try await buildWorkout(.canonicalAMA1720Sample)

    let snapshot = workoutSnapshot(workout)

    XCTAssertEqual(
      snapshot,
      """
      name: Upper Body Push - Hypertrophy Focus
      sport: strength
      duration: 55
      description: nil
      intervals:
      - warmup seconds=600 target=bench press warm-up sets at 40 kg
      - reps sets=4 reps=8 name=bench press load=82.5kg rest=120 follow=nil
      - rest seconds=120
      - reps sets=3 reps=10 name=incline bench press load=60kg rest=90 follow=nil
      - rest seconds=90
      - reps sets=3 reps=12 name=dumbbell fly load=14kg rest=60 follow=nil
      - rest seconds=60
      - reps sets=3 reps=12 name=tricep pushdown load=25kg rest=60 follow=nil
      - rest seconds=60
      - reps sets=3 reps=10 name=skull crusher load=20kg rest=60 follow=nil
      """
    )
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
    XCTAssertEqual(SuggestWorkoutState.empty, SuggestWorkoutState.empty)
    // AMA-1803 P1: state.error now carries CTAError. Two errors with
    // the same shape compare equal; different shapes don't.
    XCTAssertEqual(
      SuggestWorkoutState.error(.unknown(description: "a")),
      SuggestWorkoutState.error(.unknown(description: "a"))
    )
    XCTAssertNotEqual(
      SuggestWorkoutState.error(.unknown(description: "a")),
      SuggestWorkoutState.error(.unknown(description: "b"))
    )
    XCTAssertNotEqual(SuggestWorkoutState.idle, SuggestWorkoutState.loading)
  }

  // MARK: - Helpers

  private func buildWorkout(_ response: SuggestWorkoutResponse) async throws -> Workout {
    mockAPI.suggestWorkoutResult = .success(response)
    await viewModel.suggestWorkout()
    guard case .success(let workout) = viewModel.state else {
      XCTFail("Expected success state, got \(viewModel.state)")
      throw TestError.unexpectedState
    }
    return workout
  }

  private func makeDependencies(apiService: APIServiceProviding) -> AppDependencies {
    AppDependencies(
      apiService: apiService,
      pairingService: MockPairingService(),
      audioService: MockAudioService(),
      progressStore: MockProgressStore(),
      watchSession: MockWatchSession(),
      chatStreamService: MockChatStreamService()
    )
  }

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @escaping () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
    while !predicate() {
      if ContinuousClock.now >= deadline {
        XCTFail("Timed out waiting for condition")
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  private func assertReps(
    _ interval: WorkoutInterval?,
    sets: Int?,
    reps: Int,
    name: String,
    load: String?,
    restSec: Int?,
    followAlongUrl: String?
  ) {
    guard
      case .reps(
        let actualSets,
        let actualReps,
        let actualName,
        let actualLoad,
        let actualRestSec,
        let actualFollowAlongUrl
      ) = interval
    else {
      XCTFail("Expected reps interval, got \(String(describing: interval))")
      return
    }

    XCTAssertEqual(actualSets, sets)
    XCTAssertEqual(actualReps, reps)
    XCTAssertEqual(actualName, name)
    XCTAssertEqual(actualLoad, load)
    XCTAssertEqual(actualRestSec, restSec)
    XCTAssertEqual(actualFollowAlongUrl, followAlongUrl)
  }

  private func workoutSnapshot(_ workout: Workout) -> String {
    var lines = [
      "name: \(workout.name)",
      "sport: \(workout.sport.rawValue)",
      "duration: \(workout.duration)",
      "description: \(workout.description ?? "nil")",
      "intervals:",
    ]
    lines.append(contentsOf: workout.intervals.map { "- \(snapshotLine(for: $0))" })
    return lines.joined(separator: "\n")
  }

  private func snapshotLine(for interval: WorkoutInterval) -> String {
    switch interval {
    case .warmup(let seconds, let target):
      return "warmup seconds=\(seconds) target=\(target ?? "nil")"
    case .cooldown(let seconds, let target):
      return "cooldown seconds=\(seconds) target=\(target ?? "nil")"
    case .time(let seconds, let target):
      return "time seconds=\(seconds) target=\(target ?? "nil")"
    case .reps(let sets, let reps, let name, let load, let restSec, let followAlongUrl):
      return [
        "reps sets=\(sets.map(String.init) ?? "nil")",
        "reps=\(reps)",
        "name=\(name)",
        "load=\(load ?? "nil")",
        "rest=\(restSec.map(String.init) ?? "nil")",
        "follow=\(followAlongUrl ?? "nil")",
      ].joined(separator: " ")
    case .distance(let meters, let target):
      return "distance meters=\(meters) target=\(target ?? "nil")"
    case .repeat(let reps, let intervals):
      return "repeat reps=\(reps) intervals=\(intervals.count)"
    case .rest(let seconds):
      return "rest seconds=\(seconds.map(String.init) ?? "nil")"
    }
  }

  // MARK: - AMA-1803 P1: typed CTAError in state.error

  func testSuggest_unauthorized_publishesUnauthenticatedCTAError() async {
    mockAPI.suggestWorkoutResult = .failure(APIError.unauthorized)

    await viewModel.suggestWorkout()

    guard case .error(let cta) = viewModel.state else {
      return XCTFail("expected .error, got \(viewModel.state)")
    }
    if case .unauthenticated = cta {
      // ok
    } else {
      XCTFail("APIError.unauthorized must classify as .unauthenticated, got \(cta)")
    }
    XCTAssertFalse(cta.isRetryable, "unauthenticated must NOT show Retry — user has to sign in")
  }

  func testSuggest_5xx_publishesRetryableHTTPCTAError() async {
    mockAPI.suggestWorkoutResult = .failure(APIError.serverError(503))

    await viewModel.suggestWorkout()

    guard case .error(let cta) = viewModel.state else {
      return XCTFail("expected .error, got \(viewModel.state)")
    }
    guard case .http(let status, _, _) = cta else {
      return XCTFail("expected .http, got \(cta)")
    }
    XCTAssertEqual(status, 503)
    XCTAssertTrue(cta.isRetryable, "503 is transient — must offer Retry")
  }

  func testSuggest_4xx_publishesNonRetryableHTTPCTAError() async {
    mockAPI.suggestWorkoutResult = .failure(APIError.serverError(404))

    await viewModel.suggestWorkout()

    guard case .error(let cta) = viewModel.state else {
      return XCTFail("expected .error, got \(viewModel.state)")
    }
    guard case .http(let status, _, _) = cta else {
      return XCTFail("expected .http, got \(cta)")
    }
    XCTAssertEqual(status, 404)
    XCTAssertFalse(cta.isRetryable, "404 is deterministic — must NOT show Retry")
  }

  func testSuggest_lyingSuccess_publishesLyingSuccessCTAError() async {
    // Backend returns 200 with `success:false` (the AMA-1798 path).
    // CTAError.map detects the body shape and surfaces error_code so
    // the View can show "Coach is unavailable (COACH_DOWN)".
    let body = "{\"success\":false,\"message\":\"Coach is unavailable\",\"error_code\":\"COACH_DOWN\"}"
    mockAPI.suggestWorkoutResult = .failure(APIError.serverErrorWithBody(200, body))

    await viewModel.suggestWorkout()

    guard case .error(let cta) = viewModel.state else {
      return XCTFail("expected .error, got \(viewModel.state)")
    }
    guard case .lyingSuccess(let message, let errorCode, _) = cta else {
      return XCTFail("expected .lyingSuccess, got \(cta)")
    }
    XCTAssertEqual(message, "Coach is unavailable")
    XCTAssertEqual(errorCode, "COACH_DOWN")
    XCTAssertFalse(cta.isRetryable, "lying-success is deterministic — Retry would re-fail")
    XCTAssertEqual(cta.userMessage, "Coach is unavailable (COACH_DOWN)")
  }

  func testSuggest_offline_publishesRetryableNetworkCTAError() async {
    mockAPI.suggestWorkoutResult = .failure(
      APIError.networkError(URLError(.notConnectedToInternet))
    )

    await viewModel.suggestWorkout()

    guard case .error(let cta) = viewModel.state else {
      return XCTFail("expected .error, got \(viewModel.state)")
    }
    guard case .network(let code, _) = cta else {
      return XCTFail("expected .network, got \(cta)")
    }
    XCTAssertEqual(code, .notConnectedToInternet)
    XCTAssertTrue(cta.isRetryable, "offline is transient — must offer Retry")
    XCTAssertEqual(cta.userMessage, "No internet connection.")
  }

  func testSuggest_decodingError_publishesNonRetryableDecodingCTAError() async {
    struct Dummy: Codable { let x: Int }
    let badJSON = Data("{}".utf8)
    var underlying: Error!
    do {
      _ = try JSONDecoder().decode(Dummy.self, from: badJSON)
    } catch {
      underlying = error
    }
    mockAPI.suggestWorkoutResult = .failure(APIError.decodingError(underlying))

    await viewModel.suggestWorkout()

    guard case .error(let cta) = viewModel.state else {
      return XCTFail("expected .error, got \(viewModel.state)")
    }
    if case .decoding = cta {
      // ok
    } else {
      XCTFail("expected .decoding, got \(cta)")
    }
    XCTAssertFalse(cta.isRetryable, "decoding error is a bug — must NOT show Retry")
  }

  func testSuggest_AnnotatedAPIError_propagatesRequestId() async {
    // AMA-1808 wrapper carries the X-Request-ID; CTAError.map must
    // surface it so the user-facing Report breadcrumb correlates with
    // AMA-1805's server-side capture.
    let annotated = AnnotatedAPIError(
      .serverError(500),
      requestId: "req-from-suggest-endpoint"
    )
    mockAPI.suggestWorkoutResult = .failure(annotated)

    await viewModel.suggestWorkout()

    guard case .error(let cta) = viewModel.state else {
      return XCTFail("expected .error, got \(viewModel.state)")
    }
    XCTAssertEqual(cta.requestId, "req-from-suggest-endpoint")
  }

  func testRetry_afterFailure_cyclesBackToSuccess() async throws {
    // The View calls viewModel.suggestWorkout() again on Retry tap.
    // Verify the state machine cycles correctly so the user sees the
    // new outcome instead of the stale error.
    mockAPI.suggestWorkoutResult = .failure(APIError.serverError(503))
    await viewModel.suggestWorkout()
    guard case .error = viewModel.state else {
      return XCTFail("expected initial failure, got \(viewModel.state)")
    }

    mockAPI.suggestWorkoutResult = .success(
      SuggestWorkoutResponse(
        blocks: [.reps(sets: 3, reps: 10, name: "Squat", load: nil, restSec: 60, followAlongUrl: nil)],
        warmUp: nil,
        cooldown: nil,
        name: "Retry Win",
        sport: .strength,
        durationSeconds: 600,
        description: nil
      )
    )
    await viewModel.suggestWorkout()

    guard case .success(let workout) = viewModel.state else {
      return XCTFail("expected .success after retry, got \(viewModel.state)")
    }
    XCTAssertEqual(workout.name, "Retry Win")
  }

  func testSuggestAnotherFailureClearsPreviousSuggestion() async {
    mockAPI.suggestWorkoutResult = .success(
      SuggestWorkoutResponse(
        blocks: [.time(seconds: 300, target: "zone 2")],
        warmUp: nil,
        cooldown: nil,
        name: "First Suggestion",
        sport: .running,
        durationSeconds: 300,
        description: nil
      )
    )
    await viewModel.suggestWorkout()
    XCTAssertEqual(viewModel.suggestedWorkout?.name, "First Suggestion")

    mockAPI.suggestWorkoutResult = .failure(APIError.serverError(503))
    await viewModel.suggestAnother()

    guard case .error = viewModel.state else {
      return XCTFail("expected .error after failed swap, got \(viewModel.state)")
    }
    XCTAssertNil(viewModel.suggestedWorkout)
  }

  private enum TestError: Error {
    case unexpectedState
  }
}

private final class DelayedSuggestWorkoutAPIService: MockAPIService {
  private let response: SuggestWorkoutResponse
  private var continuation: CheckedContinuation<Void, Never>?

  init(response: SuggestWorkoutResponse) {
    self.response = response
    super.init()
  }

  override func suggestWorkout(request: SuggestWorkoutRequest) async throws
    -> SuggestWorkoutResponse
  {
    precondition(
      continuation == nil, "Delayed suggestWorkout mock only supports one pending request")
    suggestWorkoutCalled = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    return response
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

extension SuggestWorkoutResponse {
  fileprivate static func single(kind interval: WorkoutInterval) -> SuggestWorkoutResponse {
    SuggestWorkoutResponse(
      blocks: [interval],
      warmUp: nil,
      cooldown: nil,
      name: nil,
      sport: nil,
      durationSeconds: nil,
      description: nil
    )
  }

  fileprivate static let canonicalAMA1720Sample = SuggestWorkoutResponse(
    blocks: [
      .reps(
        sets: 4,
        reps: 8,
        name: "bench press",
        load: "82.5 kg",
        restSec: 120,
        followAlongUrl: nil
      ),
      .reps(
        sets: 3,
        reps: 10,
        name: "incline bench press",
        load: "60.0 kg",
        restSec: 90,
        followAlongUrl: nil
      ),
      .reps(
        sets: 3,
        reps: 12,
        name: "dumbbell fly",
        load: "14.0 kg",
        restSec: 60,
        followAlongUrl: nil
      ),
      .reps(
        sets: 3,
        reps: 12,
        name: "tricep pushdown",
        load: "25.0 kg",
        restSec: 60,
        followAlongUrl: nil
      ),
      .reps(
        sets: 3,
        reps: 10,
        name: "skull crusher",
        load: "20.0 kg",
        restSec: 60,
        followAlongUrl: nil
      ),
    ],
    warmUp: WarmUpCooldown(seconds: 600, target: "bench press warm-up sets at 40 kg"),
    cooldown: nil,
    name: "Upper Body Push - Hypertrophy Focus",
    sport: .strength,
    durationSeconds: 55,
    description: nil
  )
}
