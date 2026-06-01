//
//  EquipmentProfileViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1995: Equipment Profile L1/L2/L3 coverage.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class EquipmentProfileViewModelTests: XCTestCase {
    private var api: MockAPIService!
    private var viewModel: EquipmentProfileViewModel!

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
        viewModel = EquipmentProfileViewModel(apiService: api)
    }

    override func tearDown() async throws {
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testLoad_nilEquipmentShowsHonestEmptyStateWithBodyweightDefault() async {
        api.getCoachingProfileResult = .success(profile(equipment: nil))

        await viewModel.load()

        XCTAssertTrue(api.getCoachingProfileCalled)
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.selectedCount, 3)
        for item in EquipmentProfileViewModel.bodyweightCategory.items {
            XCTAssertTrue(viewModel.isSelected(item, in: EquipmentProfileViewModel.bodyweightCategory))
        }
        XCTAssertFalse(viewModel.isDirty)
    }

    func testLoad_noCoachingProfileShowsEmptySetupStateWithoutError() async {
        api.getCoachingProfileResult = .success(nil)

        await viewModel.load()

        XCTAssertTrue(api.getCoachingProfileCalled)
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.ctaError)
        XCTAssertNil(viewModel.lastFailedAction)
        XCTAssertEqual(viewModel.selectedCount, 3)
        XCTAssertFalse(viewModel.isDirty)

        viewModel.selectLocation(.gym)
        XCTAssertTrue(viewModel.saveEnabled, "Draft defaults should allow creating the profile from the setup state")
    }

    func testLoad_existingEquipmentShowsContentAndMapsGeneratedInventory() async {
        let inventory = equipment(
            strength: ["dumbbells": true, "barbell": true],
            cardio: ["rower": true],
            bodyweight: ["pull_up_bar": true, "rings": false, "paralettes": false],
            mobility: ["bands": true],
            dumbbellRangeKg: 32,
            location: "gym"
        )
        api.getCoachingProfileResult = .success(profile(equipment: inventory))

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.trainingLocation, .gym)
        XCTAssertEqual(viewModel.dumbbellRangeKg, 32)
        XCTAssertTrue(viewModel.isSelected(.init(id: "dumbbells", label: "Dumbbells"), in: EquipmentProfileViewModel.strengthCategory))
        XCTAssertTrue(viewModel.isSelected(.init(id: "rower", label: "Rower"), in: EquipmentProfileViewModel.cardioCategory))
        XCTAssertTrue(viewModel.isSelected(.init(id: "bands", label: "Bands"), in: EquipmentProfileViewModel.mobilityCategory))
        XCTAssertFalse(viewModel.isDirty)
    }

    func testLoad_errorMatrixMapsToCTAError() async {
        let cases: [(Error, (CTAError) -> Bool, String)] = [
            (URLError(.notConnectedToInternet), { if case .network(let code, _) = $0 { return code == .notConnectedToInternet }; return false }, "network"),
            (APIError.serverError(503), { if case .http(let status, _, _) = $0 { return status == 503 }; return false }, "http"),
            (APIError.serverErrorWithBody(200, "{\"success\":false,\"message\":\"Nope\",\"error_code\":\"BAD\"}"), { if case .lyingSuccess(let message, let code, _) = $0 { return message == "Nope" && code == "BAD" }; return false }, "lyingSuccess"),
            (APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad shape"))), { if case .decoding = $0 { return true }; return false }, "decoding")
        ]

        for (error, matcher, label) in cases {
            api = MockAPIService()
            api.getCoachingProfileResult = .failure(error)
            viewModel = EquipmentProfileViewModel(apiService: api)

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

    func testLoadErrorDismissKeepsErrorStateInsteadOfFakeEmptyForm() async {
        api.getCoachingProfileResult = .failure(URLError(.notConnectedToInternet))

        await viewModel.load()
        viewModel.dismissError()

        XCTAssertNil(viewModel.ctaError)
        guard case .error = viewModel.state else {
            return XCTFail("Dismissed load error must remain in error state, got \(viewModel.state)")
        }
        XCTAssertFalse(viewModel.saveEnabled)
    }

    func testGeneratedDecoderHandlesOpenAPISnakeCaseCodingKeys() throws {
        let json = """
        {
          "created_at": "2026-05-28T00:00:00Z",
          "equipment": {
            "bodyweight": { "pull_up_bar": true },
            "cardio": {},
            "dumbbellRangeKg": 24,
            "mobility": {},
            "strength": { "dumbbells": true },
            "trainingLocation": "gym"
          },
          "experience_level": "intermediate",
          "primary_goal": "general_fitness",
          "sessions_per_week": 3,
          "updated_at": "2026-05-28T00:00:00Z",
          "user_id": "user-1"
        }
        """.data(using: .utf8)!

        let decoded = try APIService.makeGeneratedDecoder().decode(Components.Schemas.CoachingProfile.self, from: json)

        XCTAssertEqual(decoded.userId, "user-1")
        XCTAssertEqual(decoded.experienceLevel, "intermediate")
        XCTAssertEqual(decoded.equipment?.trainingLocation, "gym")
        XCTAssertEqual(decoded.equipment?.dumbbellRangeKg, 24)
    }

    func testSaveBuildsGeneratedUpsertPersistsAndClearsDirtyState() async {
        api.getCoachingProfileResult = .success(profile(equipment: nil))
        await viewModel.load()

        viewModel.toggleItem(.init(id: "dumbbells", label: "Dumbbells"), in: EquipmentProfileViewModel.strengthCategory)
        viewModel.setDumbbellRangeKg(120)
        viewModel.selectLocation(.gym)
        XCTAssertTrue(viewModel.saveEnabled)

        await viewModel.save()

        XCTAssertTrue(api.upsertCoachingProfileCalled)
        let upsert = try! XCTUnwrap(api.lastCoachingProfileUpsert)
        XCTAssertEqual(upsert.experienceLevel, "intermediate")
        XCTAssertEqual(upsert.primaryGoal, "general_fitness")
        XCTAssertEqual(upsert.sessionsPerWeek, 3)
        XCTAssertEqual(upsert.equipment?.trainingLocation, "gym")
        XCTAssertEqual(upsert.equipment?.dumbbellRangeKg, 100)
        XCTAssertEqual(upsert.equipment?.strength?.additionalProperties["dumbbells"], true)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertFalse(viewModel.saveEnabled)
    }

    func testSave_errorMatrixMapsToCTAErrorAndKeepsDirtyState() async {
        let cases: [(Error, (CTAError) -> Bool, String)] = [
            (URLError(.timedOut), { if case .network(let code, _) = $0 { return code == .timedOut }; return false }, "network"),
            (APIError.serverError(500), { if case .http(let status, _, _) = $0 { return status == 500 }; return false }, "http"),
            (APIError.serverErrorWithBody(200, "{\"success\":false,\"error_code\":\"NO_SAVE\"}"), { if case .lyingSuccess(_, let code, _) = $0 { return code == "NO_SAVE" }; return false }, "lyingSuccess"),
            (APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad shape"))), { if case .decoding = $0 { return true }; return false }, "decoding")
        ]

        for (error, matcher, label) in cases {
            api = MockAPIService()
            api.getCoachingProfileResult = .success(profile(equipment: nil))
            api.upsertCoachingProfileResult = .failure(error)
            viewModel = EquipmentProfileViewModel(apiService: api)
            await viewModel.load()
            viewModel.selectLocation(.outdoor)

            await viewModel.save()

            let ctaError = try! XCTUnwrap(viewModel.ctaError, "Missing CTAError for \(label)")
            XCTAssertTrue(matcher(ctaError), "Wrong CTAError mapping for \(label): \(ctaError)")
            XCTAssertEqual(viewModel.lastFailedAction, .save)
            XCTAssertTrue(viewModel.isDirty)
            XCTAssertEqual(viewModel.state, .empty)
        }
    }

    func testLabelToEnumMappingAndDumbbellBounds() {
        XCTAssertEqual(EquipmentProfileViewModel.TrainingLocation.value(for: "Home"), "home")
        XCTAssertEqual(EquipmentProfileViewModel.TrainingLocation.value(for: "Commercial gym"), "gym")
        XCTAssertEqual(EquipmentProfileViewModel.TrainingLocation.value(for: "Outdoor"), "outdoor")
        XCTAssertEqual(EquipmentProfileViewModel.TrainingLocation.value(for: "Travelling"), "travel")
        XCTAssertEqual(EquipmentProfileViewModel.clampDumbbellRange(1), 5)
        XCTAssertEqual(EquipmentProfileViewModel.clampDumbbellRange(55), 55)
        XCTAssertEqual(EquipmentProfileViewModel.clampDumbbellRange(101), 100)
    }

    func testCategoryCollapseSearchLocationAndDirtySaveEnabled() async {
        api.getCoachingProfileResult = .success(profile(equipment: nil))
        await viewModel.load()
        XCTAssertFalse(viewModel.saveEnabled)

        viewModel.toggleCategory(EquipmentProfileViewModel.cardioCategory)
        XCTAssertTrue(viewModel.isCollapsed(EquipmentProfileViewModel.cardioCategory))
        viewModel.toggleCategory(EquipmentProfileViewModel.cardioCategory)
        XCTAssertFalse(viewModel.isCollapsed(EquipmentProfileViewModel.cardioCategory))

        viewModel.searchText = "row"
        let filtered = viewModel.filteredCategories()
        XCTAssertEqual(filtered.map(\.id), ["cardio"])
        XCTAssertEqual(filtered.first?.items.map(\.id), ["rower"])

        viewModel.selectLocation(.travel)
        XCTAssertEqual(viewModel.trainingLocation, .travel)
        XCTAssertTrue(viewModel.saveEnabled)
    }

    func testFixtureServiceSaveRoundTripsThroughGeneratedPUTThenGET() async throws {
        let fixture = FixtureAPIService()
        let first = try await fixture.getCoachingProfile()
        let unwrappedFirst = try XCTUnwrap(first)
        XCTAssertNil(unwrappedFirst.equipment)

        let saved = try await fixture.upsertCoachingProfile(.init(
            equipment: equipment(strength: ["dumbbells": true], dumbbellRangeKg: 24, location: "gym"),
            experienceLevel: unwrappedFirst.experienceLevel,
            primaryGoal: unwrappedFirst.primaryGoal,
            sessionsPerWeek: unwrappedFirst.sessionsPerWeek
        ))
        XCTAssertEqual(saved.equipment?.trainingLocation, "gym")
        XCTAssertEqual(saved.equipment?.dumbbellRangeKg, 24)

        let fetched = try await fixture.getCoachingProfile()
        let unwrappedFetched = try XCTUnwrap(fetched)
        XCTAssertEqual(unwrappedFetched.equipment?.trainingLocation, "gym")
        XCTAssertEqual(unwrappedFetched.equipment?.strength?.additionalProperties["dumbbells"], true)
    }

    func testEditProfileLoadMapsBackendFieldsAndEmptyState() async {
        let editViewModel = EditProfileViewModel(apiService: api)
        api.getCoachingProfileResult = .success(profile(equipment: nil, goals: [], sessionsPerWeek: 3, sessionDurationMinutes: nil))

        await editViewModel.load()

        XCTAssertEqual(editViewModel.state, .empty)
        XCTAssertEqual(editViewModel.experience, .intermediate)
        XCTAssertEqual(editViewModel.sessionsPerWeek, 3)
        XCTAssertEqual(editViewModel.sessionDurationMinutes, 45)
        XCTAssertEqual(editViewModel.weeklyHoursLabel, "2.2 hr / week")
        XCTAssertFalse(editViewModel.canSave)
    }

    func testEditProfileLoadNoCoachingProfileShowsSetupStateWithoutError() async {
        let editViewModel = EditProfileViewModel(apiService: api)
        api.getCoachingProfileResult = .success(nil)

        await editViewModel.load()

        XCTAssertEqual(editViewModel.state, .empty)
        XCTAssertNil(editViewModel.ctaError)
        XCTAssertNil(editViewModel.lastFailedAction)
        XCTAssertEqual(editViewModel.experience, .intermediate)
        XCTAssertEqual(editViewModel.sessionsPerWeek, 3)
        XCTAssertEqual(editViewModel.sessionDurationMinutes, 45)
        XCTAssertFalse(editViewModel.canSave)
    }

    func testEditProfileLoadWithGoalsShowsContentAndFields() async {
        let editViewModel = EditProfileViewModel(apiService: api)
        api.getCoachingProfileResult = .success(
            profile(
                equipment: nil,
                experienceLevel: "advanced",
                goals: [
                    .init(date: "2026-10-11", event: "Chicago Marathon", _type: "race"),
                    .init(strengthSubtype: "lose_weight", _type: "strength")
                ],
                sessionsPerWeek: 4,
                sessionDurationMinutes: 60
            )
        )

        await editViewModel.load()

        XCTAssertEqual(editViewModel.state, .content)
        XCTAssertEqual(editViewModel.experience, .advanced)
        XCTAssertEqual(editViewModel.sessionsPerWeek, 4)
        XCTAssertEqual(editViewModel.sessionDurationMinutes, 60)
        XCTAssertEqual(editViewModel.weeklyHoursLabel, "4 hr / week")
        XCTAssertTrue(editViewModel.isSelected(.race))
        XCTAssertTrue(editViewModel.isSelected(.strength))
        XCTAssertEqual(editViewModel.raceEvent, "Chicago Marathon")
        XCTAssertEqual(editViewModel.raceDate, "2026-10-11")
        XCTAssertEqual(editViewModel.strengthSubtype, .loseWeight)
        XCTAssertFalse(editViewModel.canSave)
    }

    func testEditProfileEditAndSaveRoundTripsWithLoadBeforePut() async throws {
        let editViewModel = EditProfileViewModel(apiService: api)
        let initialEquipment = equipment(strength: ["dumbbells": true], dumbbellRangeKg: 24, location: "gym")
        api.getCoachingProfileResult = .success(
            profile(equipment: initialEquipment, goals: [.init(_type: "health")], sessionsPerWeek: 3, sessionDurationMinutes: 45)
        )
        await editViewModel.load()

        let latestEquipment = equipment(cardio: ["rower": true], location: "outdoor")
        api.getCoachingProfileResult = .success(
            profile(equipment: latestEquipment, goals: [.init(_type: "health")], sessionsPerWeek: 3, sessionDurationMinutes: 45)
        )
        editViewModel.experience = .beginner
        editViewModel.setSessionsPerWeek(5)
        editViewModel.setSessionDurationMinutes(75)
        editViewModel.toggleGoal(.mobility)
        XCTAssertTrue(editViewModel.canSave)

        await editViewModel.save()

        XCTAssertTrue(api.upsertCoachingProfileCalled)
        let upsert = try XCTUnwrap(api.lastCoachingProfileUpsert)
        XCTAssertEqual(upsert.equipment, latestEquipment, "Save must preserve the freshest profile fields from load-before-PUT")
        XCTAssertEqual(upsert.experienceLevel, "beginner")
        XCTAssertEqual(upsert.sessionsPerWeek, 5)
        XCTAssertEqual(upsert.sessionDurationMinutes, 75)
        XCTAssertEqual(Set(upsert.goals?.map { $0._type } ?? []), ["health", "mobility"])
        XCTAssertNil(editViewModel.ctaError)
        XCTAssertFalse(editViewModel.canSave)
    }

    func testEditProfileSaveFailureUsesCTAErrorAndInlineRetrySurvivesToastDismissal() async throws {
        let editViewModel = EditProfileViewModel(apiService: api)
        api.getCoachingProfileResult = .success(profile(equipment: nil, goals: [.init(_type: "health")]))
        await editViewModel.load()
        editViewModel.setSessionsPerWeek(6)
        api.upsertCoachingProfileResult = .failure(URLError(.timedOut))

        await editViewModel.save()

        let ctaError = try XCTUnwrap(editViewModel.ctaError)
        if case .network(let code, _) = ctaError {
            XCTAssertEqual(code, .timedOut)
        } else {
            XCTFail("Expected network CTAError, got \(ctaError)")
        }
        XCTAssertEqual(editViewModel.lastFailedAction, .save)
        XCTAssertTrue(editViewModel.canSave)
        XCTAssertTrue(editViewModel.showsInlineSaveRetry)

        editViewModel.dismissError()
        XCTAssertNil(editViewModel.ctaError)
        XCTAssertTrue(editViewModel.showsInlineSaveRetry, "Inline retry must survive toast dismissal")

        api.upsertCoachingProfileResult = nil
        await editViewModel.retryLastAction()
        XCTAssertNil(editViewModel.ctaError)
        XCTAssertFalse(editViewModel.showsInlineSaveRetry)
    }

    func testEditProfileLoadErrorMapsCTAErrorAndRetry() async {
        let editViewModel = EditProfileViewModel(apiService: api)
        api.getCoachingProfileResult = .failure(APIError.serverErrorWithBody(503, "{\"detail\":\"profile unavailable\"}"))

        await editViewModel.load()

        guard case .error(let ctaError) = editViewModel.state else {
            return XCTFail("Expected load error, got \(editViewModel.state)")
        }
        XCTAssertEqual(editViewModel.ctaError, ctaError)
        XCTAssertEqual(editViewModel.lastFailedAction, .load)

        api.getCoachingProfileResult = .success(profile(equipment: nil, goals: [.init(_type: "mobility")]))
        await editViewModel.retryLastAction()
        XCTAssertEqual(editViewModel.state, .content)
        XCTAssertTrue(editViewModel.isSelected(.mobility))
        XCTAssertNil(editViewModel.ctaError)
    }

    private func profile(
        equipment: Components.Schemas.EquipmentInventory?,
        experienceLevel: String = "intermediate",
        goals: [Components.Schemas.GoalEntry]? = nil,
        sessionsPerWeek: Int = 3,
        sessionDurationMinutes: Int? = nil
    ) -> Components.Schemas.CoachingProfile {
        Components.Schemas.CoachingProfile(
            createdAt: "2026-05-28T00:00:00Z",
            equipment: equipment,
            experienceLevel: experienceLevel,
            goals: goals,
            primaryGoal: "general_fitness",
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
