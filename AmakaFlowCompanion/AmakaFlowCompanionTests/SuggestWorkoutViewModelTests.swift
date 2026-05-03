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

  func testRequestSuggestion_showsOnboardingWhenNoProfile() {
    viewModel.requestSuggestion()
    XCTAssertEqual(viewModel.state, .needsOnboarding)
    XCTAssertFalse(mockAPI.suggestWorkoutCalled)
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
    mockAPI.suggestWorkoutResult = .success(.single(kind: .time(seconds: 300, target: "zone 2")))

    await viewModel.suggestWorkout(durationMinutes: 30, focusMuscleGroups: ["quads"], notes: "easy")

    XCTAssertTrue(mockAPI.suggestWorkoutCalled)
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

  func testSuggestWorkout_errorSetsErrorStateAndLeavesSuggestionNil() async {
    mockAPI.suggestWorkoutResult = .failure(APIError.serverError(500))

    await viewModel.suggestWorkout()

    XCTAssertTrue(mockAPI.suggestWorkoutCalled)
    XCTAssertNil(viewModel.suggestedWorkout)
    guard case .error(let message) = viewModel.state else {
      XCTFail("Expected error state, got \(viewModel.state)")
      return
    }
    XCTAssertFalse(message.isEmpty)
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
    let response = SuggestWorkoutResponse.single(
      kind: .reps(
        sets: 4,
        reps: 8,
        name: "bench press",
        load: "82.5 kg",
        restSec: 120,
        followAlongUrl: "https://example.com/bench"
      )
    )

    let workout = try await buildWorkout(response)

    XCTAssertEqual(workout.duration, 120)
    assertReps(
      workout.intervals.first,
      sets: 4,
      reps: 8,
      name: "bench press",
      load: "82.5 kg",
      restSec: 120,
      followAlongUrl: "https://example.com/bench"
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

    XCTAssertEqual(workout.intervals, [repeatInterval])
    XCTAssertEqual(workout.duration, 60)
  }

  func testBuildWorkout_translatesRestIntervalKind() async throws {
    let workout = try await buildWorkout(.single(kind: .rest(seconds: 75)))
    XCTAssertEqual(workout.intervals, [.rest(seconds: 75)])
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
    XCTAssertEqual(workout.intervals, [.rest(seconds: nil)])
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
      - reps sets=4 reps=8 name=bench press load=82.5 kg rest=120 follow=nil
      - reps sets=3 reps=10 name=incline bench press load=60.0 kg rest=90 follow=nil
      - reps sets=3 reps=12 name=dumbbell fly load=14.0 kg rest=60 follow=nil
      - reps sets=3 reps=12 name=tricep pushdown load=25.0 kg rest=60 follow=nil
      - reps sets=3 reps=10 name=skull crusher load=20.0 kg rest=60 follow=nil
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
    XCTAssertEqual(SuggestWorkoutState.error("a"), SuggestWorkoutState.error("a"))
    XCTAssertNotEqual(SuggestWorkoutState.error("a"), SuggestWorkoutState.error("b"))
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
