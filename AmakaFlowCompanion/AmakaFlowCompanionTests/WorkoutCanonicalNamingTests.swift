//
//  WorkoutCanonicalNamingTests.swift
//  AmakaFlowCompanionTests
//
//  Ownership and persistence rules for canonical workout naming.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutCanonicalNamingTests: XCTestCase {

    func testAutoMatchNeverReplacesUserPick() {
        var state = CanonicalMatchState(
            canonicalId: "tempo_run",
            source: .userPick,
            chip: "Tempo Run"
        )

        state.applyAutoMatchIfEligible(match(canonicalId: "leg_day", displayName: "Leg Day"))

        XCTAssertEqual(state.canonicalId, "tempo_run")
        XCTAssertEqual(state.source, .userPick)
        XCTAssertEqual(state.chipDisplayName, "Tempo Run")
    }

    func testAutoMatchNeverReplacesPreset() {
        var state = CanonicalMatchState(
            canonicalId: "tempo_run",
            source: .preset,
            chip: "Tempo Run"
        )

        state.applyAutoMatchIfEligible(match(canonicalId: "leg_day", displayName: "Leg Day"))

        XCTAssertEqual(state.canonicalId, "tempo_run")
        XCTAssertEqual(state.source, .preset)
        XCTAssertEqual(state.chipDisplayName, "Tempo Run")
    }

    func testClearSuppressionUsesServerNormalizedTitleVerbatim() {
        var state = CanonicalMatchState()

        state.clear(serverNormalizedTitle: "tempo run")

        XCTAssertEqual(state.clearSuppressionKey, "tempo run")
        XCTAssertTrue(state.isClearSuppressed(serverNormalizedTitle: "tempo run"))
        XCTAssertFalse(state.isClearSuppressed(serverNormalizedTitle: "tempo  run"))
    }

    func testSuppressedAutoMatchDoesNotRestoreClearedValue() {
        var state = CanonicalMatchState()
        state.clear(serverNormalizedTitle: "tempo run")

        state.applyAutoMatchIfEligible(match(normalizedTitle: "tempo run"))

        XCTAssertNil(state.canonicalId)
        XCTAssertNil(state.source)
        XCTAssertNil(state.chipDisplayName)
    }

    func testDifferentServerNormalizedTitleCanAutoMatchAfterClear() {
        var state = CanonicalMatchState()
        state.clear(serverNormalizedTitle: "tempo run")

        state.applyAutoMatchIfEligible(match(normalizedTitle: "tempo run intervals"))

        XCTAssertEqual(state.canonicalId, "tempo_run")
        XCTAssertEqual(state.source, .auto)
        XCTAssertEqual(state.chipDisplayName, "Tempo Run")
    }

    func testOfflineSavePersistsLastKnownNotNull() {
        let state = CanonicalMatchState(
            canonicalId: "tempo_run",
            source: .auto,
            chip: "Tempo Run"
        )

        let persist = state.valuesForSave(onlineMatchFailedOrOffline: true)

        XCTAssertEqual(persist.canonicalId, "tempo_run")
        XCTAssertEqual(persist.source, .auto)
    }

    func testFailedFreshAutoPersistsNull() {
        let state = CanonicalMatchState()

        let persist = state.valuesForSave(onlineMatchFailedOrOffline: true)

        XCTAssertNil(persist.canonicalId)
        XCTAssertNil(persist.source)
    }

    func testUserPickAndPresetSetOwnedValues() {
        var state = CanonicalMatchState()

        state.applyUserPick(canonicalId: "leg_day", displayName: "Leg Day")
        XCTAssertEqual(state.valuesForSave().canonicalId, "leg_day")
        XCTAssertEqual(state.valuesForSave().source, .userPick)

        state.applyPreset(canonicalId: "tempo_run", displayName: "Tempo Run")
        XCTAssertEqual(state.valuesForSave().canonicalId, "tempo_run")
        XCTAssertEqual(state.valuesForSave().source, .preset)
    }

    func testPresetEditorSeedSetsTitleCanonicalIdAndPresetSource() {
        let preset = workoutType(id: "tempo_run", displayName: "Tempo Run", aiPreset: true)

        let seed = WorkoutTypePresetEditorSeed(preset: preset)

        XCTAssertEqual(seed.title, "Tempo Run")
        XCTAssertEqual(seed.matchState.canonicalId, "tempo_run")
        XCTAssertEqual(seed.matchState.source, .preset)
        XCTAssertEqual(seed.matchState.chipDisplayName, "Tempo Run")
    }

    func testPresetCanonicalIdSurvivesTitleRename() async {
        let apiService = MockAPIService()
        let seed = WorkoutTypePresetEditorSeed(
            preset: workoutType(id: "tempo_run", displayName: "Tempo Run", aiPreset: true)
        )
        let controller = WorkoutTypeMatchController(apiService: apiService, state: seed.matchState)

        await controller.onTitleIdle(title: "Friday Threshold Session")

        XCTAssertFalse(apiService.matchWorkoutTypeCalled)
        XCTAssertEqual(controller.canonicalId, "tempo_run")
        XCTAssertEqual(controller.canonicalSource, .preset)
    }

    func testMapperSaveBodyEmitsCanonicalFieldsInSnakeCase() throws {
        let request = WorkoutSaveRequest(
            name: "Tempo Run",
            sport: "running",
            intervals: [
                WorkoutSaveInterval(type: "time", name: "Run", seconds: 1200)
            ],
            canonicalId: "tempo_run",
            canonicalSource: .userPick,
            canonicalFieldsProvided: true
        )

        let body = try APIService.mapperSaveBody(from: request, source: "manual")

        XCTAssertEqual(body["canonical_id"] as? String, "tempo_run")
        XCTAssertEqual(body["canonical_source"] as? String, "user_pick")
        XCTAssertNil(body["canonicalId"])
        XCTAssertNil(body["canonicalSource"])
    }

    func testMapperSaveBodyEmitsExplicitNullsWhenCanonicalMatchIsCleared() throws {
        let request = WorkoutSaveRequest(
            name: "Tempo Run",
            sport: "running",
            intervals: [
                WorkoutSaveInterval(type: "time", name: "Run", seconds: 1200)
            ],
            canonicalFieldsProvided: true
        )

        let body = try APIService.mapperSaveBody(from: request, source: "manual")

        XCTAssertTrue(body["canonical_id"] is NSNull)
        XCTAssertTrue(body["canonical_source"] is NSNull)
    }

    func testMapperSaveBodyOmitsMalformedCanonicalPairs() throws {
        let intervals = [
            WorkoutSaveInterval(type: "time", name: "Run", seconds: 1200)
        ]
        let idOnlyRequest = WorkoutSaveRequest(
            name: "Tempo Run",
            sport: "running",
            intervals: intervals,
            canonicalId: "tempo_run"
        )
        let sourceOnlyRequest = WorkoutSaveRequest(
            name: "Tempo Run",
            sport: "running",
            intervals: intervals,
            canonicalSource: .auto
        )

        let idOnlyBody = try APIService.mapperSaveBody(from: idOnlyRequest, source: "manual")
        let sourceOnlyBody = try APIService.mapperSaveBody(from: sourceOnlyRequest, source: "manual")

        XCTAssertNil(idOnlyBody["canonical_id"])
        XCTAssertNil(idOnlyBody["canonical_source"])
        XCTAssertNil(sourceOnlyBody["canonical_id"])
        XCTAssertNil(sourceOnlyBody["canonical_source"])
    }

    func testMatchResponseDecodesBFFCamelCaseContract() throws {
        let data = Data(
            #"""
            {
              "canonicalId": "tempo_run",
              "displayName": "Tempo Run",
              "confidence": 1.0,
              "method": "exact",
              "normalizedTitle": "tempo run",
              "candidates": [
                {"canonicalId": "tempo_run", "displayName": "Tempo Run", "confidence": 1.0}
              ]
            }
            """#.utf8
        )

        let response = try APIService.makeDecoder().decode(WorkoutTypeMatchResponse.self, from: data)

        XCTAssertEqual(response.canonicalId, "tempo_run")
        XCTAssertEqual(response.normalizedTitle, "tempo run")
        XCTAssertEqual(response.candidates.first?.displayName, "Tempo Run")
    }

    func testControllerDoesNotCallMatchForUserOwnedValue() async {
        let apiService = MockAPIService()
        var controller = WorkoutTypeMatchController(
            apiService: apiService,
            state: CanonicalMatchState(
                canonicalId: "tempo_run",
                source: .userPick,
                chip: "Tempo Run"
            )
        )

        await controller.onTitleIdle(title: "Leg Day")

        XCTAssertFalse(apiService.matchWorkoutTypeCalled)
        XCTAssertEqual(controller.canonicalId, "tempo_run")
        XCTAssertEqual(controller.canonicalSource, .userPick)
    }

    func testControllerSoftFailurePreservesLastKnownAndDoesNotBlockSave() async {
        let apiService = MockAPIService()
        apiService.matchWorkoutTypeResult = .failure(
            APIError.network(underlying: URLError(.notConnectedToInternet))
        )
        var controller = WorkoutTypeMatchController(
            apiService: apiService,
            state: CanonicalMatchState(
                canonicalId: "tempo_run",
                source: .auto,
                chip: "Tempo Run"
            )
        )

        await controller.onTitleIdle(title: "Tempo intervals")
        let values = await controller.onSave(online: false)

        XCTAssertTrue(apiService.matchWorkoutTypeCalled)
        XCTAssertEqual(values.canonicalId, "tempo_run")
        XCTAssertEqual(values.source, .auto)
    }

    func testControllerRematchesIdleSuccessOnOnlineSave() async {
        let apiService = MockAPIService()
        apiService.matchWorkoutTypeResult = .success(match())
        var controller = WorkoutTypeMatchController(apiService: apiService)

        await controller.onTitleIdle(title: "Tempo Run")
        let values = await controller.onSave(online: true)

        XCTAssertEqual(apiService.matchWorkoutTypeCallCount, 2)
        XCTAssertEqual(apiService.lastMatchWorkoutTypeTitle, "Tempo Run")
        XCTAssertEqual(values.canonicalId, "tempo_run")
        XCTAssertEqual(values.source, .auto)
    }

    func testSuccessfulMatchShowsChipAndRetainsTopCandidates() async {
        let apiService = MockAPIService()
        let candidates = [
            WorkoutTypeCandidate(
                canonicalId: "tempo_run",
                displayName: "Tempo Run",
                confidence: 1
            ),
            WorkoutTypeCandidate(
                canonicalId: "interval_run",
                displayName: "Interval Run",
                confidence: 0.72
            )
        ]
        apiService.matchWorkoutTypeResult = .success(
            match(candidates: candidates)
        )
        var controller = WorkoutTypeMatchController(apiService: apiService)

        await controller.onTitleIdle(title: "Tempo Run")

        XCTAssertEqual(controller.chipDisplayName, "Tempo Run")
        XCTAssertEqual(controller.lastCandidates, candidates)
    }

    func testClearLoadedUserPickObtainsSuppressionBeforeOnlineSave() async {
        let apiService = MockAPIService()
        apiService.matchWorkoutTypeResult = .success(match(normalizedTitle: "tempo run"))
        let controller = WorkoutTypeMatchController(
            apiService: apiService,
            state: CanonicalMatchState(
                canonicalId: "tempo_run",
                source: .userPick,
                chip: "Tempo Run"
            )
        )
        controller.noteTitleForSave("Tempo Run")

        await controller.clear()
        let values = await controller.onSave(online: true)

        XCTAssertEqual(apiService.matchWorkoutTypeCallCount, 1)
        XCTAssertEqual(controller.clearSuppressionNormalizedTitle, "tempo run")
        XCTAssertNil(controller.chipDisplayName)
        XCTAssertNil(values.canonicalId)
        XCTAssertNil(values.source)
    }

    func testClearFetchesNormalizationForCurrentTitleInsteadOfUsingStaleMatch() async {
        let apiService = MockAPIService()
        apiService.matchWorkoutTypeResult = .success(match(normalizedTitle: "tempo run"))
        let controller = WorkoutTypeMatchController(apiService: apiService)
        await controller.onTitleIdle(title: "Tempo Run")
        apiService.matchWorkoutTypeResult = .success(
            match(
                canonicalId: "leg_day",
                displayName: "Leg Day",
                normalizedTitle: "leg day"
            )
        )
        controller.noteTitleForSave("Leg Day")

        await controller.clear()

        XCTAssertEqual(apiService.matchWorkoutTypeCallCount, 2)
        XCTAssertEqual(apiService.lastMatchWorkoutTypeTitle, "Leg Day")
        XCTAssertEqual(controller.clearSuppressionNormalizedTitle, "leg day")
    }

    func testNoMatchResponseClearsPriorAutoChip() async {
        let apiService = MockAPIService()
        apiService.matchWorkoutTypeResult = .success(
            match(canonicalId: nil, displayName: nil, method: "none")
        )
        let controller = WorkoutTypeMatchController(
            apiService: apiService,
            state: CanonicalMatchState(
                canonicalId: "tempo_run",
                source: .auto,
                chip: "Tempo Run"
            )
        )

        await controller.onTitleIdle(title: "Unmatched workout")

        XCTAssertNil(controller.canonicalId)
        XCTAssertNil(controller.canonicalSource)
        XCTAssertNil(controller.chipDisplayName)
    }

    func testClearHidesChipAndProducesNullSaveValues() async {
        let apiService = MockAPIService()
        apiService.matchWorkoutTypeResult = .success(match())
        var controller = WorkoutTypeMatchController(apiService: apiService)
        await controller.onTitleIdle(title: "Tempo Run")

        await controller.clear()
        let values = await controller.onSave(online: false)

        XCTAssertNil(controller.chipDisplayName)
        XCTAssertNil(values.canonicalId)
        XCTAssertNil(values.source)
    }

    func testUserPickSurvivesTitleRename() async {
        let apiService = MockAPIService()
        apiService.matchWorkoutTypeResult = .success(
            match(canonicalId: "leg_day", displayName: "Leg Day")
        )
        var controller = WorkoutTypeMatchController(apiService: apiService)
        controller.applyUserPick(canonicalId: "tempo_run", displayName: "Tempo Run")

        await controller.onTitleIdle(title: "Renamed workout")

        XCTAssertFalse(apiService.matchWorkoutTypeCalled)
        XCTAssertEqual(controller.canonicalId, "tempo_run")
        XCTAssertEqual(controller.canonicalSource, .userPick)
        XCTAssertEqual(controller.chipDisplayName, "Tempo Run")
    }

    func testLoadedKnownIdResolvesChipButUnknownIdDoesNot() {
        let catalog = [
            workoutType(id: "tempo_run", displayName: "Tempo Run")
        ]
        var known = CanonicalMatchState(canonicalId: "tempo_run", source: .auto)
        var unknown = CanonicalMatchState(canonicalId: "retired_type", source: .auto)

        known.resolveLoadedDisplayName(from: catalog)
        unknown.resolveLoadedDisplayName(from: catalog)

        XCTAssertEqual(known.chipDisplayName, "Tempo Run")
        XCTAssertNil(unknown.chipDisplayName)
    }

    @MainActor
    func testEditorSavePassesCanonicalFields() async {
        let apiService = MockAPIService()
        let dependencies = AppDependencies(
            apiService: apiService,
            pairingService: MockPairingService(),
            audioService: MockAudioService(),
            progressStore: MockProgressStore(),
            watchSession: MockWatchSession(),
            chatStreamService: MockChatStreamService()
        )
        let viewModel = WorkoutEditorViewModel(dependencies: dependencies)
        viewModel.name = "Tempo Run"
        viewModel.intervals = [
            WorkoutSaveInterval(type: "time", name: "Run", seconds: 1200)
        ]
        viewModel.canonicalId = "tempo_run"
        viewModel.canonicalSource = .userPick

        await viewModel.save()

        XCTAssertEqual(apiService.lastSaveWorkoutRequest?.canonicalId, "tempo_run")
        XCTAssertEqual(apiService.lastSaveWorkoutRequest?.canonicalSource, CanonicalSource.userPick)
    }

    private func match(
        canonicalId: String? = "tempo_run",
        displayName: String? = "Tempo Run",
        normalizedTitle: String = "tempo run",
        method: String = "exact",
        candidates: [WorkoutTypeCandidate] = []
    ) -> WorkoutTypeMatchResponse {
        WorkoutTypeMatchResponse(
            canonicalId: canonicalId,
            displayName: displayName,
            confidence: 1,
            method: method,
            normalizedTitle: normalizedTitle,
            candidates: candidates
        )
    }

    private func workoutType(
        id: String,
        displayName: String,
        aiPreset: Bool = false
    ) -> WorkoutTypeItem {
        WorkoutTypeItem(
            id: id,
            category: "cardio",
            format: "continuous",
            focus: [],
            displayName: displayName,
            aliases: [],
            aiPreset: aiPreset,
            equipment: [],
            platformTags: [:]
        )
    }
}
