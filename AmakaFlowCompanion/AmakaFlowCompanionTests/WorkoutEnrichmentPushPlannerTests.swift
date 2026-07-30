//
//  WorkoutEnrichmentPushPlannerTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2336: pre-push offer computation (spec 2026-07-27 §5).
//  Pure logic — blocks + tombstones + prefs in, offer rows out.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutEnrichmentPushPlannerTests: XCTestCase {
    // MARK: - Fixtures

    private func benchBlock(
        restSec: Int? = nil,
        restOpen: Bool? = nil,
        exerciseId: String? = nil,
        warmupSets: [WarmupSetRow]? = nil
    ) -> SocialImportBlock {
        SocialImportBlock(
            label: "Main",
            rounds: 1,
            exercises: [
                SocialImportExercise(
                    name: "Bench Press",
                    sets: 4,
                    reps: 8,
                    restSeconds: restSec,
                    exerciseId: exerciseId,
                    warmupSets: warmupSets,
                    restOpen: restOpen
                )
            ],
            type: "sets"
        )
    }

    private var warmupBlock: SocialImportBlock {
        SocialImportBlock(
            label: "Warm-up",
            rounds: 1,
            exercises: [SocialImportExercise(name: "Row 500m")],
            type: StructureBlockType.warmup.rawValue
        )
    }

    private var cooldownBlock: SocialImportBlock {
        SocialImportBlock(
            label: "Cool-down",
            rounds: 1,
            exercises: [SocialImportExercise(name: "Walk")],
            type: StructureBlockType.cooldown.rawValue
        )
    }

    private var cooldownEnabledPrefs: WorkoutPreferences {
        var prefs = WorkoutPreferences.defaults
        prefs.cooldown = CooldownPrefs(
            enabled: true,
            activities: [EnrichmentActivityPref(name: "Easy Bike", durationSec: 300)]
        )
        return prefs
    }

    // MARK: - Offers

    func testMissingKindsAreOfferedCheckedWhenPrefsEnabled() {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )

        XCTAssertTrue(plan.hasOffers)
        XCTAssertEqual(
            plan.offers.map(\.kind),
            [.sessionWarmup, .betweenSetRest, .exerciseWarmupSets]
        )
        XCTAssertTrue(plan.offers.allSatisfy(\.isChecked))
        XCTAssertTrue(plan.offers.allSatisfy { !$0.wasTombstoned })
    }

    func testCooldownIsNotOfferedWhilePrefsHaveItOff() {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(plan.offer(.cooldown))
    }

    func testPresenceByTypeHidesTheSoftSectionOffers() {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [warmupBlock, benchBlock(), cooldownBlock],
            tombstones: [],
            prefs: cooldownEnabledPrefs
        )
        XCTAssertNil(plan.offer(.sessionWarmup))
        XCTAssertNil(plan.offer(.cooldown))
    }

    func testExistingRestIntentIsNotOffered() {
        let timed = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(restSec: 90)],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(timed.offer(.betweenSetRest))

        let open = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(restOpen: true)],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(open.offer(.betweenSetRest))
    }

    func testExistingWarmupSetsAndExcludedNamesAreNotOffered() {
        let present = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(warmupSets: [WarmupSetRow(reps: 8)])],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(present.offer(.exerciseWarmupSets))

        var excludedPrefs = WorkoutPreferences.defaults
        excludedPrefs.exerciseWarmupSets.excludeExerciseKeys = ["  BENCH   press "]
        let excluded = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: excludedPrefs
        )
        XCTAssertNil(excluded.offer(.exerciseWarmupSets))
    }

    func testCardioOnlyWorkoutGetsNoWarmupSetOffer() {
        let cardio = SocialImportBlock(
            label: "Main",
            rounds: 1,
            exercises: [SocialImportExercise(name: "Row", seconds: 600)],
            type: "sets"
        )
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [cardio],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(plan.offer(.exerciseWarmupSets))
    }

    // MARK: - Tombstoned kinds appear unchecked

    func testTombstonedKindIsOfferedUnchecked() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [EnrichmentTombstone(kind: .sessionWarmup)],
            prefs: .defaults
        )
        let offer = try XCTUnwrap(plan.offer(.sessionWarmup))
        XCTAssertFalse(offer.isChecked)
        XCTAssertTrue(offer.wasTombstoned)
        XCTAssertFalse(plan.defaultCheckedKinds.contains(.sessionWarmup))
    }

    func testWarmupSetsOfferIsUncheckedOnlyWhenEveryCandidateIsTombstoned() throws {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Bench Press", sets: 4, reps: 8, exerciseId: "wex_bench"),
                    SocialImportExercise(name: "Barbell Row", sets: 4, reps: 8, exerciseId: "wex_row")
                ],
                type: "sets"
            )
        ]

        let partial = WorkoutEnrichmentPushPlanner.plan(
            blocks: blocks,
            tombstones: [EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_bench")],
            prefs: .defaults
        )
        let partialOffer = try XCTUnwrap(partial.offer(.exerciseWarmupSets))
        XCTAssertTrue(partialOffer.isChecked)
        XCTAssertTrue(partialOffer.wasTombstoned)
        XCTAssertEqual(partialOffer.tombstonedExerciseIds, ["wex_bench"])

        let all = WorkoutEnrichmentPushPlanner.plan(
            blocks: blocks,
            tombstones: [
                EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_bench"),
                EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_row")
            ],
            prefs: .defaults
        )
        let allOffer = try XCTUnwrap(all.offer(.exerciseWarmupSets))
        XCTAssertFalse(allOffer.isChecked)
        XCTAssertEqual(allOffer.tombstonedExerciseIds.sorted(), ["wex_bench", "wex_row"])
    }

    func testNothingToOfferWhenEverythingIsPresent() {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [
                warmupBlock,
                benchBlock(restSec: 90, warmupSets: [WarmupSetRow(reps: 8)])
            ],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertFalse(plan.hasOffers)
    }

    // MARK: - Applying the decision

    func testApplyDisablesUncheckedKindsAndKeepsTheirTombstones() throws {
        let tombstones = [EnrichmentTombstone(kind: .sessionWarmup)]
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: tombstones,
            prefs: .defaults
        )

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [.betweenSetRest]),
            prefs: .defaults,
            tombstones: tombstones
        )

        XCTAssertTrue(application.prefs.betweenSetRest.enabled)
        XCTAssertFalse(application.prefs.sessionWarmup.enabled)
        XCTAssertFalse(application.prefs.cooldown.enabled)
        XCTAssertFalse(application.prefs.exerciseWarmupSets.enabled)
        XCTAssertEqual(application.tombstones, tombstones)
        XCTAssertTrue(application.clearedTombstones.isEmpty)
        XCTAssertTrue(application.appliesAnything)
    }

    func testApplyClearsTombstonesForCheckedKinds() throws {
        let tombstones = [
            EnrichmentTombstone(kind: .sessionWarmup),
            EnrichmentTombstone(kind: .betweenSetRest)
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: tombstones,
            prefs: .defaults
        )

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [.sessionWarmup]),
            prefs: .defaults,
            tombstones: tombstones
        )

        XCTAssertEqual(application.clearedTombstones, [EnrichmentTombstone(kind: .sessionWarmup)])
        XCTAssertTrue(application.tombstones.contains(where: { $0.kind == .betweenSetRest }))
        XCTAssertFalse(application.tombstones.contains(where: { $0.kind == .sessionWarmup }))
    }

    func testApplyClearsPerExerciseWarmupSetTombstones() throws {
        let tombstones = [EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_bench")]
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(exerciseId: "wex_bench")],
            tombstones: tombstones,
            prefs: .defaults
        )
        // Fully tombstoned → offer starts unchecked; checking is an explicit re-opt-in.
        XCTAssertFalse(try XCTUnwrap(plan.offer(.exerciseWarmupSets)).isChecked)

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [.exerciseWarmupSets]),
            prefs: .defaults,
            tombstones: tombstones
        )

        XCTAssertFalse(
            application.tombstones.contains(
                where: { $0.kind == .exerciseWarmupSets && $0.exerciseId == "wex_bench" }
            )
        )
        XCTAssertEqual(application.clearedTombstones, tombstones)
        // Unchecked offers (mobility / rest) are rejected → tombstoned.
        XCTAssertTrue(application.tombstones.contains(where: { $0.kind == .sessionWarmup }))
        XCTAssertTrue(application.tombstones.contains(where: { $0.kind == .betweenSetRest }))
    }

    func testApplyKeepsPartialWarmupSetTombstonesWhenLeftChecked() throws {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Bench Press", sets: 4, reps: 8, exerciseId: "wex_bench"),
                    SocialImportExercise(name: "Barbell Row", sets: 4, reps: 8, exerciseId: "wex_row")
                ],
                type: "sets"
            )
        ]
        let tombstones = [EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_bench")]
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: blocks,
            tombstones: tombstones,
            prefs: .defaults
        )
        let offer = try XCTUnwrap(plan.offer(.exerciseWarmupSets))
        XCTAssertTrue(offer.isChecked)
        XCTAssertTrue(offer.wasTombstoned)

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [.exerciseWarmupSets]),
            prefs: .defaults,
            tombstones: tombstones
        )

        XCTAssertTrue(
            application.tombstones.contains(
                where: { $0.kind == .exerciseWarmupSets && $0.exerciseId == "wex_bench" }
            )
        )
        XCTAssertTrue(application.clearedTombstones.isEmpty)
        XCTAssertTrue(application.tombstones.contains(where: { $0.kind == .sessionWarmup }))
        XCTAssertTrue(application.tombstones.contains(where: { $0.kind == .betweenSetRest }))
    }

    func testApplyHonoursRestOverrides() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )

        let timed = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.betweenSetRest],
                restSecOverride: 120,
                restOpenOverride: false
            ),
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertEqual(timed.prefs.betweenSetRest.restSec, 120)
        XCTAssertFalse(timed.prefs.betweenSetRest.restOpen)

        // Open rest must clear rest_sec — contradictory intent is a backend 400.
        let open = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.betweenSetRest],
                restSecOverride: 120,
                restOpenOverride: true
            ),
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertNil(open.prefs.betweenSetRest.restSec)
        XCTAssertTrue(open.prefs.betweenSetRest.restOpen)
    }

    func testApplyWithNothingCheckedAppliesNothing() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: []),
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertFalse(application.appliesAnything)
        // AMA-2346: rejecting every offer still persists tombstones.
        XCTAssertTrue(application.needsPersist)
        XCTAssertTrue(application.tombstones.contains(where: { $0.kind == .sessionWarmup }))
        XCTAssertTrue(application.tombstones.contains(where: { $0.kind == .betweenSetRest }))
        XCTAssertTrue(application.rejectedTombstones.contains(where: { $0.kind == .sessionWarmup }))
        XCTAssertTrue(application.rejectedTombstones.contains(where: { $0.kind == .betweenSetRest }))
    }

    // MARK: - Coordinator apply (AMA-2346)

    @MainActor
    func testApplyPersistsRejectTombstonesWhenEnrichFails() async {
        let mock = MockAPIService()
        mock.enrichWorkoutResult = .failure(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "mapper down"])
        )
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(exerciseId: "wex_bench")],
            tombstones: [],
            prefs: .defaults
        )
        let prepared = WorkoutEnrichmentPushCoordinator.Prepared(
            workoutId: "w1",
            title: "Push",
            plan: plan,
            prefs: .defaults,
            tombstones: [],
            blocksJSON: ["blocks": []]
        )
        let coordinator = WorkoutEnrichmentPushCoordinator(apiService: mock)

        // Accept rest so enrich is called; reject mobility → tombstone must persist
        // even when enrich throws.
        let outcome = await coordinator.apply(
            prepared: prepared,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [.betweenSetRest])
        )

        XCTAssertEqual(mock.enrichWorkoutCallCount, 1)
        XCTAssertTrue(outcome.applied)
        XCTAssertNotNil(outcome.note)
        XCTAssertEqual(mock.savedWorkoutBlocksJSON.count, 1)
        let savedTombs = mock.savedWorkoutBlocksJSON[0].tombstones ?? []
        XCTAssertTrue(savedTombs.contains(where: { $0.kind == .sessionWarmup }))
    }

    @MainActor
    func testApplySkipsEnrichWhenNothingCheckedButStillPersistsTombstones() async {
        let mock = MockAPIService()
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(exerciseId: "wex_bench")],
            tombstones: [],
            prefs: .defaults
        )
        let prepared = WorkoutEnrichmentPushCoordinator.Prepared(
            workoutId: "w1",
            title: "Push",
            plan: plan,
            prefs: .defaults,
            tombstones: [],
            blocksJSON: ["blocks": []]
        )
        let coordinator = WorkoutEnrichmentPushCoordinator(apiService: mock)

        let outcome = await coordinator.apply(
            prepared: prepared,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [])
        )

        XCTAssertEqual(mock.enrichWorkoutCallCount, 0)
        XCTAssertTrue(outcome.applied)
        XCTAssertNil(outcome.note)
        XCTAssertEqual(mock.savedWorkoutBlocksJSON.count, 1)
        let savedTombs = mock.savedWorkoutBlocksJSON[0].tombstones ?? []
        XCTAssertTrue(savedTombs.contains(where: { $0.kind == .sessionWarmup }))
        XCTAssertTrue(savedTombs.contains(where: { $0.kind == .betweenSetRest }))
    }

    func testRejectSessionWarmupTombsWhileAcceptingRest() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(exerciseId: "wex_bench")],
            tombstones: [],
            prefs: .defaults
        )
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [.betweenSetRest]),
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertFalse(application.prefs.sessionWarmup.enabled)
        XCTAssertTrue(application.prefs.betweenSetRest.enabled)
        XCTAssertTrue(application.tombstones.contains(where: { $0.kind == .sessionWarmup }))
        XCTAssertFalse(application.tombstones.contains(where: { $0.kind == .betweenSetRest }))
        XCTAssertTrue(
            application.tombstones.contains(
                where: { $0.kind == .exerciseWarmupSets && $0.exerciseId == "wex_bench" }
            )
        )
    }

    // MARK: - blocks_json parse (no invented defaults)

    func testBlocksJSONParseKeepsDeclaredFieldsAndInventsNothing() throws {
        let blocksJSON: [String: Any] = [
            "blocks": [
                [
                    "type": "warmup",
                    "label": "Warm-up",
                    "enrichment_kind": "session_warmup",
                    "structure_source": "enrichment_default",
                    "exercises": [["name": "Jump Rope"]]
                ],
                [
                    "type": "sets",
                    "label": "Main",
                    "exercises": [
                        [
                            "name": "Bench Press",
                            "sets": 4,
                            "reps": 8,
                            "exercise_id": "wex_bench",
                            "warmup_sets": [["reps": 8, "structure_source": "enrichment_default"]]
                        ]
                    ]
                ]
            ],
            "enrichment_tombstones": [["kind": "cooldown"]]
        ]

        let parsed = WorkoutEnrichmentBlocksJSON.parse(blocksJSON)

        XCTAssertTrue(WorkoutEnrichmentPresence.hasWarmupBlock(in: parsed.blocks))
        XCTAssertEqual(parsed.tombstones, [EnrichmentTombstone(kind: .cooldown)])
        let bench = try XCTUnwrap(parsed.blocks.last?.exercises.first)
        XCTAssertEqual(bench.exerciseId, "wex_bench")
        XCTAssertEqual(bench.warmupSets?.map(\.reps), [8])
        // A missing rest must stay missing — that is the gap the sheet asks about.
        XCTAssertNil(bench.restSeconds)
        XCTAssertNil(bench.restOpen)
        XCTAssertFalse(WorkoutEnrichmentPushPlanner.hasRestIntent(in: parsed.blocks))
    }

    // MARK: - Mock double

    func testMockEnrichmentMethodsRecordCalls() async throws {
        let mock = MockAPIService()
        mock.fetchWorkoutBlocksJSONResult = .success(["blocks": []])

        let prefs = try await mock.fetchWorkoutPreferences()
        XCTAssertTrue(mock.fetchWorkoutPreferencesCalled)
        XCTAssertEqual(prefs, .defaults)

        var edited = WorkoutPreferences.defaults
        edited.sessionWarmup.enabled = false
        _ = try await mock.updateWorkoutPreferences(edited)
        XCTAssertEqual(mock.lastUpdatedWorkoutPreferences, edited)

        let response = try await mock.enrichWorkout(
            EnrichRequest(blocksJSON: ["blocks": []], mode: .push)
        )
        XCTAssertEqual(mock.enrichWorkoutCallCount, 1)
        XCTAssertEqual(mock.lastEnrichRequest?.mode, .push)
        XCTAssertNotNil(response.blocksJSON["blocks"])

        _ = try await mock.fetchWorkoutBlocksJSON(workoutId: "w1")
        XCTAssertEqual(mock.lastFetchWorkoutBlocksJSONWorkoutId, "w1")

        try await mock.saveWorkoutBlocksJSON(workoutId: "w1", title: "Push", blocksJSON: ["blocks": []])
        XCTAssertEqual(mock.savedWorkoutBlocksJSON.map(\.workoutId), ["w1"])
    }

    // MARK: - Save body must satisfy the strict mapper schema

    func testSaveableWorkoutDataDropsKeysTheSaveSchemaForbids() throws {
        let enriched: [String: Any] = [
            "title": "Stale title",
            "workout_type": "strength",
            "blocks": [["type": "sets", "exercises": [["name": "Bench Press"]]]],
            "enrichment_tombstones": [["kind": "cooldown"]],
            "sync_status": "pushed",
            "metadata": ["sources": ["manual"]]
        ]

        let sanitized = APIService.saveableWorkoutData(
            enriched,
            title: "Push",
            tombstones: [EnrichmentTombstone(kind: .cooldown)]
        )

        XCTAssertEqual(sanitized["title"] as? String, "Push")
        XCTAssertNotNil(sanitized["blocks"])
        XCTAssertNil(sanitized["enrichment_tombstones"])
        XCTAssertNil(sanitized["sync_status"])
        let metadata = try XCTUnwrap(sanitized["metadata"] as? [String: Any])
        let tombstones = try XCTUnwrap(metadata["enrichment_tombstones"] as? [[String: Any]])
        XCTAssertEqual(tombstones.first?["kind"] as? String, "cooldown")
        XCTAssertEqual(metadata["sources"] as? [String], ["manual"])
    }

    func testBlocksJSONParseReadsTombstonesFromMetadata() {
        let blocksJSON: [String: Any] = [
            "blocks": [],
            "metadata": [
                "enrichment_tombstones": [["kind": "session_warmup"]]
            ]
        ]
        let parsed = WorkoutEnrichmentBlocksJSON.parse(blocksJSON)
        XCTAssertEqual(parsed.tombstones, [EnrichmentTombstone(kind: .sessionWarmup)])
    }

    // MARK: - Push body carries the structural flag

    func testGarminPushBodySendsEnrichedTrue() throws {
        let body = GarminWatchDisplayPrefs.dogfood.pushBody
        let object = try WorkoutEnrichmentJSON.object(from: body)
        XCTAssertEqual(object["enriched"] as? Bool, true)
        XCTAssertEqual(object["exercise_end"] as? String, "lap")
    }
}
