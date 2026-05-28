//
//  CoachingProfileOnboardingViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1997: multi-goal onboarding L1/L3 coverage.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class CoachingProfileOnboardingViewModelTests: XCTestCase {
    private var api: MockAPIService!
    private var viewModel: CoachingProfileOnboardingViewModel!

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
        viewModel = CoachingProfileOnboardingViewModel(apiService: api)
    }

    override func tearDown() async throws {
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testLoad_nilGoalsShowsEmptyAndDisablesContinue() async {
        api.getCoachingProfileResult = .success(profile(goals: nil))

        await viewModel.load()

        XCTAssertTrue(api.getCoachingProfileCalled)
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.selectedCount, 0)
        XCTAssertFalse(viewModel.canContinue)
    }

    func testMultiSelectAllowsLayeredGoalsAndNoneIsMutuallyExclusive() async {
        api.getCoachingProfileResult = .success(profile(goals: nil))
        await viewModel.load()

        viewModel.selectGoal(.race)
        viewModel.selectGoal(.mobility)

        XCTAssertTrue(viewModel.isSelected(.race))
        XCTAssertTrue(viewModel.isSelected(.mobility))
        XCTAssertFalse(viewModel.isSelected(.none))
        XCTAssertTrue(viewModel.canContinue)

        viewModel.selectGoal(.none)

        XCTAssertTrue(viewModel.isSelected(.none))
        XCTAssertFalse(viewModel.isSelected(.race))
        XCTAssertFalse(viewModel.isSelected(.mobility))
        XCTAssertEqual(viewModel.buildGoals().map(\._type), ["none"])

        viewModel.selectGoal(.health)

        XCTAssertTrue(viewModel.isSelected(.health))
        XCTAssertFalse(viewModel.isSelected(.none))
    }

    func testRaceExpandsEventDateAndBuildsOnlyRaceFields() async throws {
        api.getCoachingProfileResult = .success(profile(goals: nil))
        await viewModel.load()

        viewModel.selectGoal(.race)
        viewModel.raceEvent = "  Chicago Marathon  "
        viewModel.raceDate = " 2026-10-11 "

        let race = try XCTUnwrap(viewModel.buildGoals().first)
        XCTAssertEqual(race._type, "race")
        XCTAssertEqual(race.event, "Chicago Marathon")
        XCTAssertEqual(race.date, "2026-10-11")
        XCTAssertNil(race.strengthSubtype)
    }

    func testStrengthExpandsSubtypeAndBuildsOnlyStrengthFields() async throws {
        api.getCoachingProfileResult = .success(profile(goals: nil))
        await viewModel.load()

        viewModel.selectStrengthSubtype(.lookGood)

        let strength = try XCTUnwrap(viewModel.buildGoals().first)
        XCTAssertEqual(strength._type, "strength")
        XCTAssertEqual(strength.strengthSubtype, "look_good")
        XCTAssertNil(strength.event)
        XCTAssertNil(strength.date)
        XCTAssertEqual(viewModel.legacyTrainingGoal, .generalFitness)
    }

    func testLoadExistingGoalsMapsGeneratedContract() async {
        api.getCoachingProfileResult = .success(profile(goals: [
            .init(date: "2026-10-11", event: "Chicago Marathon", _type: "race"),
            .init(strengthSubtype: "build_muscle", _type: "strength"),
            .init(_type: "mobility")
        ]))

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertTrue(viewModel.isSelected(.race))
        XCTAssertTrue(viewModel.isSelected(.strength))
        XCTAssertTrue(viewModel.isSelected(.mobility))
        XCTAssertEqual(viewModel.raceEvent, "Chicago Marathon")
        XCTAssertEqual(viewModel.raceDate, "2026-10-11")
        XCTAssertEqual(viewModel.strengthSubtype, .buildMuscle)
    }

    func testSavePersistsGoalsAndCarriesEquipmentAndOtherProfileFieldsForward() async throws {
        let loadedEquipment = equipment(strength: ["dumbbells": true], dumbbellRangeKg: 32, location: "gym")
        let latestEquipment = equipment(cardio: ["bike": true], mobility: ["foam_roller": true], location: "home")
        api.getCoachingProfileResult = .success(profile(
            equipment: loadedEquipment,
            goals: nil,
            injuriesLimitations: "No overhead pressing",
            preferredDays: ["monday", "wednesday"],
            primaryGoal: "general_fitness",
            sessionDurationMinutes: 45,
            sessionsPerWeek: 4
        ))
        await viewModel.load()

        api.getCoachingProfileResult = .success(profile(
            equipment: latestEquipment,
            goals: nil,
            injuriesLimitations: "Knee-friendly conditioning",
            preferredDays: ["tuesday", "thursday"],
            primaryGoal: "general_fitness",
            sessionDurationMinutes: 60,
            sessionsPerWeek: 5
        ))
        viewModel.daysPerWeek = 4
        viewModel.selectGoal(.race)
        viewModel.raceEvent = "Hyrox Dallas"
        viewModel.raceDate = "2026-11-07"
        viewModel.selectStrengthSubtype(.loseWeight)

        let didSave = await viewModel.save()

        XCTAssertTrue(didSave)
        XCTAssertTrue(api.upsertCoachingProfileCalled)
        let upsert = try XCTUnwrap(api.lastCoachingProfileUpsert)
        XCTAssertEqual(upsert.equipment, latestEquipment)
        XCTAssertEqual(upsert.experienceLevel, "intermediate")
        XCTAssertEqual(upsert.injuriesLimitations, "Knee-friendly conditioning")
        XCTAssertEqual(upsert.preferredDays, ["tuesday", "thursday"])
        XCTAssertEqual(upsert.primaryGoal, "general_fitness")
        XCTAssertEqual(upsert.sessionDurationMinutes, 60)
        XCTAssertEqual(upsert.sessionsPerWeek, 4)
        XCTAssertEqual(upsert.goals?.map(\._type), ["race", "strength"])
        XCTAssertEqual(upsert.goals?.first?.event, "Hyrox Dallas")
        XCTAssertEqual(upsert.goals?.first?.date, "2026-11-07")
        XCTAssertEqual(upsert.goals?.last?.strengthSubtype, "lose_weight")
    }

    func testLoadErrorMatrixMapsToCTAError() async {
        let cases: [(Error, (CTAError) -> Bool, String)] = [
            (URLError(.notConnectedToInternet), { if case .network(let code, _) = $0 { return code == .notConnectedToInternet }; return false }, "network"),
            (APIError.serverError(503), { if case .http(let status, _, _) = $0 { return status == 503 }; return false }, "http"),
            (APIError.serverErrorWithBody(200, "{\"success\":false,\"message\":\"Nope\",\"error_code\":\"BAD\"}"), { if case .lyingSuccess(let message, let code, _) = $0 { return message == "Nope" && code == "BAD" }; return false }, "lyingSuccess"),
            (APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad shape"))), { if case .decoding = $0 { return true }; return false }, "decoding")
        ]

        for (error, matcher, label) in cases {
            api = MockAPIService()
            api.getCoachingProfileResult = .failure(error)
            viewModel = CoachingProfileOnboardingViewModel(apiService: api)

            await viewModel.load()

            guard case .error(let ctaError) = viewModel.state else {
                XCTFail("Expected error state for \(label), got \(viewModel.state)")
                continue
            }
            XCTAssertTrue(matcher(ctaError), "Wrong CTAError mapping for \(label): \(ctaError)")
            XCTAssertEqual(viewModel.ctaError, ctaError)
            XCTAssertEqual(viewModel.lastFailedAction, .load)
        }
    }

    func testSaveErrorMatrixMapsToCTAErrorAndDoesNotClearSelection() async throws {
        let cases: [(Error, (CTAError) -> Bool, String)] = [
            (URLError(.timedOut), { if case .network(let code, _) = $0 { return code == .timedOut }; return false }, "network"),
            (APIError.serverError(500), { if case .http(let status, _, _) = $0 { return status == 500 }; return false }, "http"),
            (APIError.serverErrorWithBody(200, "{\"success\":false,\"error_code\":\"NO_SAVE\"}"), { if case .lyingSuccess(_, let code, _) = $0 { return code == "NO_SAVE" }; return false }, "lyingSuccess"),
            (APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad shape"))), { if case .decoding = $0 { return true }; return false }, "decoding")
        ]

        for (error, matcher, label) in cases {
            api = MockAPIService()
            api.getCoachingProfileResult = .success(profile(goals: nil))
            api.upsertCoachingProfileResult = .failure(error)
            viewModel = CoachingProfileOnboardingViewModel(apiService: api)
            await viewModel.load()
            viewModel.selectGoal(.health)

            let didSave = await viewModel.save()

            XCTAssertFalse(didSave)
            let ctaError = try XCTUnwrap(viewModel.ctaError, "Missing CTAError for \(label)")
            XCTAssertTrue(matcher(ctaError), "Wrong CTAError mapping for \(label): \(ctaError)")
            XCTAssertEqual(viewModel.lastFailedAction, .save)
            XCTAssertTrue(viewModel.isSelected(.health))
            XCTAssertEqual(viewModel.state, .content)
        }
    }

    func testViewAccessibilityIdentifiersCoverCardsExpansionRemoveAndContinue() {
        let ids = CoachingProfileOnboardingViewModel.accessibilityIdentifiers()

        XCTAssertTrue(ids.contains("goal_card_race"))
        XCTAssertTrue(ids.contains("goal_card_strength"))
        XCTAssertTrue(ids.contains("goal_card_health"))
        XCTAssertTrue(ids.contains("goal_card_mobility"))
        XCTAssertTrue(ids.contains("goal_card_none"))
        XCTAssertTrue(ids.contains("goal_remove_race"))
        XCTAssertTrue(ids.contains("goal_race_event"))
        XCTAssertTrue(ids.contains("goal_race_date"))
        XCTAssertTrue(ids.contains("goal_strength_build_muscle"))
        XCTAssertTrue(ids.contains("goal_strength_lose_weight"))
        XCTAssertTrue(ids.contains("goal_strength_look_good"))
        XCTAssertTrue(ids.contains("coaching_onboarding_continue"))
    }

    func testFixtureServiceGoalsRoundTripThroughGeneratedPUTThenGET() async throws {
        let fixture = FixtureAPIService()
        let first = try await fixture.getCoachingProfile()
        XCTAssertNil(first.goals)

        let saved = try await fixture.upsertCoachingProfile(.init(
            equipment: first.equipment,
            experienceLevel: first.experienceLevel,
            goals: [.init(event: "Hyrox Dallas", _type: "race"), .init(_type: "mobility")],
            primaryGoal: first.primaryGoal,
            sessionsPerWeek: first.sessionsPerWeek
        ))
        XCTAssertEqual(saved.goals?.map(\._type), ["race", "mobility"])

        let fetched = try await fixture.getCoachingProfile()
        XCTAssertEqual(fetched.goals?.map(\._type), ["race", "mobility"])
        XCTAssertEqual(fetched.goals?.first?.event, "Hyrox Dallas")
    }

    private func profile(
        equipment: Components.Schemas.EquipmentInventory? = nil,
        goals: [Components.Schemas.GoalEntry]? = nil,
        injuriesLimitations: String? = nil,
        preferredDays: [String]? = nil,
        primaryGoal: String? = "general_fitness",
        sessionDurationMinutes: Int? = nil,
        sessionsPerWeek: Int = 3
    ) -> Components.Schemas.CoachingProfile {
        Components.Schemas.CoachingProfile(
            createdAt: "2026-05-28T00:00:00Z",
            equipment: equipment,
            experienceLevel: "intermediate",
            goals: goals,
            injuriesLimitations: injuriesLimitations,
            preferredDays: preferredDays,
            primaryGoal: primaryGoal,
            sessionDurationMinutes: sessionDurationMinutes,
            sessionsPerWeek: sessionsPerWeek,
            updatedAt: "2026-05-28T00:00:00Z",
            userId: "user-1"
        )
    }

    private func equipment(
        strength: [String: Bool] = [:],
        cardio: [String: Bool] = [:],
        bodyweight: [String: Bool] = [:],
        mobility: [String: Bool] = [:],
        dumbbellRangeKg: Int? = nil,
        location: String = "home"
    ) -> Components.Schemas.EquipmentInventory {
        Components.Schemas.EquipmentInventory(
            bodyweight: .init(additionalProperties: bodyweight),
            cardio: .init(additionalProperties: cardio),
            dumbbellRangeKg: dumbbellRangeKg,
            mobility: .init(additionalProperties: mobility),
            strength: .init(additionalProperties: strength),
            trainingLocation: location
        )
    }
}
