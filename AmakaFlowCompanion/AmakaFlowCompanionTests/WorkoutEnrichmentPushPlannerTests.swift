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
        blockRestSec: Int? = nil,
        blockRestOpen: Bool? = nil,
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
            type: "sets",
            restSec: blockRestSec,
            restOpen: blockRestOpen
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
            [.sessionWarmup, .exerciseWarmupSets, .betweenSetRest, .cooldown]
        )
        XCTAssertEqual(
            plan.offers.filter(\.isChecked).map(\.kind),
            [.sessionWarmup, .exerciseWarmupSets, .betweenSetRest]
        )
        XCTAssertEqual(plan.offer(.cooldown)?.isChecked, false)
        XCTAssertTrue(plan.offers.allSatisfy { !$0.wasTombstoned })
    }

    /// AMA-2378 polish — Cooldown always appears on the enhance sheet (like
    /// Rest) so the athlete can opt in; prefs.enabled only controls the
    /// default check (off → unchecked).
    func testCooldownIsOfferedUncheckedWhenPrefsHaveItOff() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        let offer = try XCTUnwrap(plan.offer(.cooldown))
        XCTAssertEqual(offer.isChecked, false)
        XCTAssertFalse(offer.detail.isEmpty)
    }

    /// Leaving the default-unchecked Cooldown alone must not tombstone it
    /// (same AMA-2347 Rest contract), or enabling Settings later would stay
    /// suppressed.
    func testLeavingPrefsDisabledCooldownUncheckedDoesNotTombstone() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertEqual(plan.offer(.cooldown)?.isChecked, false)

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.sessionWarmup, .betweenSetRest, .exerciseWarmupSets]
            ),
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertFalse(application.tombstones.contains(where: { $0.kind == .cooldown }))
        XCTAssertFalse(application.rejectedTombstones.contains(where: { $0.kind == .cooldown }))
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

    /// AMA-2390 — existing block rest stays visible (checked) so the athlete can opt out.
    func testExistingRestIntentIsOfferedChecked() {
        let timed = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(blockRestSec: 90)],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertEqual(timed.offer(.betweenSetRest)?.isChecked, true)

        let open = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(blockRestOpen: true)],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertEqual(open.offer(.betweenSetRest)?.isChecked, true)
    }

    func testClearBlockRestIntentRemovesRestKeys() {
        let blocksJSON: [String: Any] = [
            "blocks": [
                [
                    "label": "Circuit",
                    "type": "circuit",
                    "rounds": 6,
                    "rest_sec": 60,
                    "rest_open": false,
                    "rest_between_rounds_sec": 60,
                    "field_provenance": [
                        "rest_sec": "user",
                        "rest_open": "user",
                        "rest_between_rounds_sec": "user",
                        "notes": "user"
                    ],
                    "exercises": [["name": "Assault Bike", "duration_sec": 180]]
                ]
            ]
        ]
        let cleared = WorkoutEnrichmentMutations.clearBlockRestIntent(in: blocksJSON)
        let block = (cleared["blocks"] as? [[String: Any]])?.first
        XCTAssertNil(block?["rest_sec"])
        XCTAssertNil(block?["rest_open"])
        XCTAssertNil(block?["rest_between_rounds_sec"])
        // Unrelated provenance (e.g. notes) must survive Rest opt-out.
        let prov = block?["field_provenance"] as? [String: Any]
        XCTAssertEqual(prov?.keys.sorted(), ["notes"])
        XCTAssertEqual(prov?["notes"] as? String, "user")
    }

    func testClearBlockRestIntentDropsEmptyProvenance() {
        let blocksJSON: [String: Any] = [
            "blocks": [
                [
                    "label": "Main",
                    "type": "sets",
                    "rest_sec": 90,
                    "field_provenance": ["rest_sec": "enrichment_default"],
                    "exercises": [["name": "Bench Press", "reps": 5]]
                ]
            ]
        ]
        let cleared = WorkoutEnrichmentMutations.clearBlockRestIntent(in: blocksJSON)
        let block = (cleared["blocks"] as? [[String: Any]])?.first
        XCTAssertNil(block?["rest_sec"])
        XCTAssertNil(block?["field_provenance"])
    }

    /// Exercise-level rest from ingest/defaults must not hide block Lap/timed rest (AMA-2348).
    func testExerciseRestSecDoesNotSuppressBlockRestOffer() {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(restSec: 90)],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNotNil(plan.offer(.betweenSetRest))
    }

    /// Dogfood Test workout: Ski Erg + Push Press with per-exercise rest still needs block rest offer.
    func testStrengthPairWithExerciseRestStillOffersBlockRest() {
        let block = SocialImportBlock(
            label: "Main",
            rounds: 1,
            exercises: [
                SocialImportExercise(name: "Ski Erg", sets: 3, distanceMeters: 500),
                SocialImportExercise(name: "Push Press", sets: 3, reps: 8, restSeconds: 45)
            ],
            type: "sets"
        )
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [block],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNotNil(plan.offer(.betweenSetRest))
    }

    /// AMA-2347 — Rest must stay visible on the Garmin send sheet even when
    /// Settings has "Offer between-set rest" off, so the user can opt in for
    /// this push (default unchecked).
    func testRestOfferedUncheckedWhenPrefsDisabled() {
        var prefs = WorkoutPreferences.defaults
        prefs.betweenSetRest.enabled = false
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: prefs
        )
        let offer = plan.offer(.betweenSetRest)
        XCTAssertNotNil(offer)
        XCTAssertEqual(offer?.isChecked, false)
    }

    /// AMA-2347 — leaving default-unchecked Rest alone must not tombstone Rest,
    /// or enabling the Settings offer later would stay suppressed.
    func testLeavingPrefsDisabledRestUncheckedDoesNotTombstone() throws {
        var prefs = WorkoutPreferences.defaults
        prefs.betweenSetRest.enabled = false
        prefs.sessionWarmup.enabled = false
        prefs.exerciseWarmupSets.enabled = false
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: prefs
        )
        XCTAssertEqual(plan.offer(.betweenSetRest)?.isChecked, false)

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: []),
            prefs: prefs,
            tombstones: []
        )
        XCTAssertFalse(application.tombstones.contains(where: { $0.kind == .betweenSetRest }))
        XCTAssertFalse(application.rejectedTombstones.contains(where: { $0.kind == .betweenSetRest }))
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

    /// AMA-2400 — Wingate circuit stations look like `1 × 0:30` (sets + duration).
    /// Warm-up ramps are for strength reps, not timed Assault Bike intervals.
    func testTimedCircuitStationWithSetsDoesNotOfferWarmupSets() {
        let circuit = SocialImportBlock(
            label: nil,
            rounds: 8,
            exercises: [
                SocialImportExercise(name: "Assault Bike", sets: 1, seconds: 30)
            ],
            type: "circuit"
        )
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [circuit],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(plan.offer(.exerciseWarmupSets))
        XCTAssertNotNil(plan.offer(.betweenSetRest))
        XCTAssertNotNil(plan.offer(.cooldown))
    }

    /// AMA-2400 / CodeRabbit — blocks_json calorie stations must parse `calories`
    /// so warmupSetCandidates can exclude them (not treat as strength ramps).
    func testBlocksJSONCalorieStationWithSetsDoesNotOfferWarmupSets() {
        let blocksJSON: [String: Any] = [
            "blocks": [
                [
                    "type": "circuit",
                    "rounds": 4,
                    "exercises": [
                        [
                            "name": "Assault Bike",
                            "sets": 1,
                            "calories": 15
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ]
        let parsed = WorkoutEnrichmentBlocksJSON.parse(blocksJSON)
        XCTAssertEqual(parsed.blocks.first?.exercises.first?.calories, 15)
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: parsed.blocks,
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(plan.offer(.exerciseWarmupSets))
    }

    /// AMA-2400 — user-owned rest left untouched must not fail Apple handoff when
    /// the mapper audits it as `skipped_already_present`.
    @MainActor
    func testIncompleteEnrichmentFalseWhenBetweenSetRestAlreadyPresent() throws {
        var prefs = WorkoutPreferences.defaults
        prefs.sessionWarmup.enabled = true
        prefs.cooldown.enabled = true
        prefs.betweenSetRest.enabled = true
        prefs.exerciseWarmupSets.enabled = false
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [
                SocialImportBlock(
                    label: nil,
                    rounds: 8,
                    exercises: [
                        SocialImportExercise(name: "Assault Bike", sets: 1, seconds: 30)
                    ],
                    type: "circuit",
                    restSec: 60
                )
            ],
            tombstones: [],
            prefs: prefs,
            target: .apple
        )
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.sessionWarmup, .betweenSetRest, .cooldown],
                restSecOverride: 60,
                restOpenOverride: false
            ),
            prefs: prefs,
            tombstones: []
        )
        let summary = EnrichmentAppliedSummary(
            prefsSource: "request_override",
            added: ["session_warmup", "cooldown"],
            skippedAlreadyPresent: ["between_set_rest"]
        )
        XCTAssertFalse(
            WorkoutEnrichmentPushCoordinator.isIncompleteEnrichment(
                application: application,
                summary: summary
            )
        )
    }

    /// AMA-2378 Task 5 — the ramp editor's "→ THEN YOUR K WORKING SETS" header
    /// needs a real working-set count per candidate, in the same order as
    /// `candidateExerciseNames` (a candidate's own `sets` is always declared —
    /// `warmupSetCandidates` requires it — but the type stays `[Int?]` so a
    /// caller with a name that has no matching candidate can still ask for an
    /// honestly-unknown count instead of a guess).
    func testWarmupSetsOfferCarriesWorkingSetCountsPerCandidateInOrder() throws {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Bench Press", sets: 4, reps: 8),
                    SocialImportExercise(name: "Barbell Row", sets: 3, reps: 8)
                ],
                type: "sets"
            )
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(blocks: blocks, tombstones: [], prefs: .defaults)
        let offer = try XCTUnwrap(plan.offer(.exerciseWarmupSets))
        XCTAssertEqual(offer.candidateExerciseNames, ["Bench Press", "Barbell Row"])
        XCTAssertEqual(offer.candidateWorkingSetCounts, [4, 3])
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
                benchBlock(
                    blockRestSec: 90,
                    warmupSets: [WarmupSetRow(reps: 8)]
                ),
                cooldownBlock
            ],
            tombstones: [],
            prefs: .defaults
        )
        // AMA-2390: Rest stays offered (checked) when block rest already exists so
        // Send as-is / unchecked can clear author rest intent.
        XCTAssertEqual(plan.offers.map(\.kind), [.betweenSetRest])
        XCTAssertEqual(plan.offer(.betweenSetRest)?.isChecked, true)
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

    // MARK: - Door-screen edits (AMA-2378 Task 6)

    /// Sequence builder edits to the mobility door must override the standing
    /// Jump Rope default rather than being silently dropped.
    func testApplyOverridesMobilityActivitiesFromDecision() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        let editedActivities = [EnrichmentActivityPref(name: "Row 500m", durationSec: 180)]

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.sessionWarmup],
                sessionWarmupActivities: editedActivities
            ),
            prefs: .defaults,
            tombstones: []
        )

        XCTAssertTrue(application.prefs.sessionWarmup.enabled)
        XCTAssertEqual(application.prefs.sessionWarmup.activities, editedActivities)
        XCTAssertNotEqual(
            application.prefs.sessionWarmup.activities,
            WorkoutPreferences.defaults.sessionWarmup.activities
        )
    }

    /// Cooldown sequence edits mirror mobility — same override path.
    func testApplyOverridesCooldownActivitiesFromDecision() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        let editedActivities = [EnrichmentActivityPref(name: "Easy Bike", durationSec: 300)]

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.cooldown],
                cooldownActivities: editedActivities
            ),
            prefs: .defaults,
            tombstones: []
        )

        XCTAssertTrue(application.prefs.cooldown.enabled)
        XCTAssertEqual(application.prefs.cooldown.activities, editedActivities)
    }

    /// A configured per-exercise ramp must land in the applied prefs' `per_exercise`.
    func testApplyIncludesPerExerciseRampInAppliedPrefs() throws {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Bench Press", sets: 4, reps: 8),
                    SocialImportExercise(name: "Barbell Row", sets: 3, reps: 8)
                ],
                type: "sets"
            )
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(blocks: blocks, tombstones: [], prefs: .defaults)
        let rampSets = [
            try RampSet(kind: .reps, value: 3),
            try RampSet(kind: .open, value: nil)
        ]
        let benchRamp = PerExerciseRamp(exerciseRef: "Bench Press", enabled: true, sets: rampSets)

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.exerciseWarmupSets],
                perExerciseRamps: [benchRamp]
            ),
            prefs: .defaults,
            tombstones: []
        )

        XCTAssertTrue(application.prefs.exerciseWarmupSets.enabled)
        XCTAssertEqual(application.prefs.exerciseWarmupSets.perExercise, [benchRamp])
        // Barbell Row was never configured in the pick screen ("skipped") —
        // it must be excluded rather than silently falling back to the
        // global default_sets scheme.
        XCTAssertTrue(application.prefs.exerciseWarmupSets.excludeExerciseKeys.contains("barbell row"))
        XCTAssertFalse(application.prefs.exerciseWarmupSets.excludeExerciseKeys.contains("bench press"))
        XCTAssertFalse(application.prefs.exerciseWarmupSets.excludeExerciseKeys.contains("Barbell Row"))
        XCTAssertFalse(application.prefs.exerciseWarmupSets.excludeExerciseKeys.contains("Bench Press"))
    }

    /// AMA-2408 — intensity notes must not ride the enrich wire (mapper prefers
    /// note over reps → WorkoutKit coerce invents reps=1).
    func testApplyStripsIntensityNotesFromPerExerciseRamps() throws {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Incline Smith Machine Press", sets: 5, reps: 10),
                    SocialImportExercise(name: "Machine Lateral Raises", sets: 3, reps: 12)
                ],
                type: "sets"
            )
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(blocks: blocks, tombstones: [], prefs: .defaults)
        let noted = [
            PerExerciseRamp(
                exerciseRef: "Incline Smith Machine Press",
                enabled: true,
                sets: [
                    try RampSet(kind: .reps, value: 11, intensityNote: "LIGHT · ~40%"),
                    try RampSet(kind: .reps, value: 11, intensityNote: "MODERATE · ~60%")
                ]
            ),
            PerExerciseRamp(
                exerciseRef: "Machine Lateral Raises",
                enabled: true,
                sets: [
                    try RampSet(kind: .reps, value: 11, intensityNote: "LIGHT · ~40%"),
                    try RampSet(kind: .reps, value: 11, intensityNote: "MODERATE · ~60%")
                ]
            )
        ]
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.exerciseWarmupSets],
                perExerciseRamps: noted
            ),
            prefs: .defaults,
            tombstones: []
        )
        let applied = try XCTUnwrap(application.prefs.exerciseWarmupSets.perExercise)
        XCTAssertEqual(applied.count, 2)
        XCTAssertEqual(Set(applied.map { ExerciseKeyNormalizer.normalize($0.exerciseRef) }), [
            "incline smith machine press",
            "machine lateral raises"
        ])
        for ramp in applied {
            XCTAssertTrue(ramp.enabled)
            XCTAssertEqual(ramp.sets.map(\.value), [11, 11])
            XCTAssertTrue(ramp.sets.allSatisfy { $0.intensityNote == nil })
        }
        XCTAssertFalse(
            application.prefs.exerciseWarmupSets.excludeExerciseKeys.contains("machine lateral raises")
        )
    }

    /// A ramp the user explicitly turned off in the pick screen is excluded too
    /// (an `enabled: false` entry means "no warm-up sets", not "use the default").
    func testApplyExcludesDisabledPerExerciseRamps() throws {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [SocialImportExercise(name: "Bench Press", sets: 4, reps: 8)],
                type: "sets"
            )
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(blocks: blocks, tombstones: [], prefs: .defaults)
        let disabledRamp = PerExerciseRamp(exerciseRef: "Bench Press", enabled: false, sets: [])

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.exerciseWarmupSets],
                perExerciseRamps: [disabledRamp]
            ),
            prefs: .defaults,
            tombstones: []
        )

        XCTAssertEqual(application.prefs.exerciseWarmupSets.perExercise, [disabledRamp])
        XCTAssertTrue(application.prefs.exerciseWarmupSets.excludeExerciseKeys.contains("bench press"))
    }

    /// Toggling a door off never requires the sheet to clear its local
    /// activities/ramps — the decision can still carry them, but they must
    /// not be applied while the kind is unchecked.
    func testApplyToggleOffDoesNotRequireClearingActivitiesInDecision() throws {
        var standing = WorkoutPreferences.defaults
        standing.sessionWarmup.activities = [EnrichmentActivityPref(name: "Ski Erg", durationSec: 120)]
        standing.exerciseWarmupSets.excludeExerciseKeys = ["leg press"]
        standing.exerciseWarmupSets.perExercise = [
            PerExerciseRamp(
                exerciseRef: "Deadlift",
                enabled: true,
                sets: [try RampSet(kind: .reps, value: 5)]
            )
        ]

        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: standing
        )
        let editedActivities = [EnrichmentActivityPref(name: "Row 500m", durationSec: 180)]
        let editedRamps = [
            PerExerciseRamp(
                exerciseRef: "Bench Press",
                enabled: true,
                sets: [try RampSet(kind: .reps, value: 8)]
            )
        ]

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.betweenSetRest],
                sessionWarmupActivities: editedActivities,
                perExerciseRamps: editedRamps
            ),
            prefs: standing,
            tombstones: []
        )

        XCTAssertFalse(application.prefs.sessionWarmup.enabled)
        // Unchecked kind → the override is ignored, standing values remain.
        XCTAssertEqual(application.prefs.sessionWarmup.activities, standing.sessionWarmup.activities)
        XCTAssertFalse(application.prefs.exerciseWarmupSets.enabled)
        XCTAssertEqual(application.prefs.exerciseWarmupSets.perExercise, standing.exerciseWarmupSets.perExercise)
        XCTAssertEqual(
            application.prefs.exerciseWarmupSets.excludeExerciseKeys,
            standing.exerciseWarmupSets.excludeExerciseKeys
        )
    }

    /// AMA-2408 — untouched warm-up door (empty perExercise) is opt-in empty:
    /// ZERO ramps, every candidate excluded. No v1 global auto-apply.
    func testUntouchedWarmupDoorAppliesZeroRampsAndExcludesAllCandidates() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.sessionWarmup, .betweenSetRest, .exerciseWarmupSets],
                perExerciseRamps: []
            ),
            prefs: .defaults,
            tombstones: []
        )

        XCTAssertEqual(
            application.prefs.sessionWarmup.activities,
            WorkoutPreferences.defaults.sessionWarmup.activities
        )
        XCTAssertEqual(application.prefs.exerciseWarmupSets.perExercise, [])
        let offer = try XCTUnwrap(plan.offer(.exerciseWarmupSets))
        let candidates = offer.candidateExerciseNames
        for name in candidates {
            XCTAssertTrue(
                application.prefs.exerciseWarmupSets.excludeExerciseKeys
                    .contains(ExerciseKeyNormalizer.normalize(name))
            )
        }
        XCTAssertTrue(
            LegacyOptInRampMigration.optInEffectiveRamps(
                prefs: application.prefs.exerciseWarmupSets,
                candidateNames: candidates
            ).isEmpty
        )
    }

    /// Production `decision.perExerciseRamps == nil` must match the empty-array opt-in path.
    func testNilPerExerciseRampsMatchesEmptyArrayExclusions() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        let emptyApplication = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.exerciseWarmupSets],
                perExerciseRamps: []
            ),
            prefs: .defaults,
            tombstones: []
        )
        let nilApplication = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.exerciseWarmupSets],
                perExerciseRamps: nil
            ),
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertEqual(
            emptyApplication.prefs.exerciseWarmupSets.perExercise,
            nilApplication.prefs.exerciseWarmupSets.perExercise
        )
        XCTAssertEqual(
            Set(emptyApplication.prefs.exerciseWarmupSets.excludeExerciseKeys),
            Set(nilApplication.prefs.exerciseWarmupSets.excludeExerciseKeys)
        )
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
            blocksJSON: ["blocks": []],
            target: .garmin
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
        XCTAssertTrue(outcome.enrichFailed)
        XCTAssertFalse(outcome.allowsAppleHandoff)
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
            blocksJSON: ["blocks": []],
            target: .garmin
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

    /// AMA-2390 — Send as-is / Rest unchecked strips author rest so Apple Workout
    /// does not keep Rest 01:00 after the sheet looked like "no changes".
    @MainActor
    func testApplyClearsBlockRestWhenRestUnchecked() async throws {
        let mock = MockAPIService()
        let blocksJSON: [String: Any] = [
            "blocks": [
                [
                    "label": "Circuit",
                    "type": "circuit",
                    "rounds": 6,
                    "rest_sec": 60,
                    "exercises": [
                        ["name": "Assault Bike", "duration_sec": 180],
                        ["name": "Ski Erg", "duration_sec": 180]
                    ]
                ]
            ]
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [
                SocialImportBlock(
                    label: "Circuit",
                    rounds: 6,
                    exercises: [
                        SocialImportExercise(name: "Assault Bike", seconds: 180),
                        SocialImportExercise(name: "Ski Erg", seconds: 180)
                    ],
                    type: "circuit",
                    restSec: 60
                )
            ],
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
        XCTAssertEqual(plan.offer(.betweenSetRest)?.isChecked, true)

        var prefs = WorkoutPreferences.defaults
        prefs.sessionWarmup.enabled = false
        prefs.exerciseWarmupSets.enabled = false
        let prepared = WorkoutEnrichmentPushCoordinator.Prepared(
            workoutId: "w-circuit",
            title: "Bike ski row repeats",
            plan: plan,
            prefs: prefs,
            tombstones: [],
            blocksJSON: blocksJSON,
            target: .apple
        )
        let outcome = await WorkoutEnrichmentPushCoordinator(apiService: mock).apply(
            prepared: prepared,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [])
        )

        XCTAssertTrue(outcome.applied)
        XCTAssertEqual(mock.enrichWorkoutCallCount, 0)
        let saved = try XCTUnwrap(mock.savedWorkoutBlocksJSON.first?.blocksJSON)
        let block = try XCTUnwrap((saved["blocks"] as? [[String: Any]])?.first)
        XCTAssertNil(block["rest_sec"])
        XCTAssertNil(block["rest_open"])
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

    // MARK: - AMA-2362 Apple Open rest

    func testAppleTargetUsesOpenRestCopyNotLap() {
        var prefs = WorkoutPreferences.defaults
        prefs.sessionWarmup = SessionWarmupPrefs(
            enabled: true,
            activities: [EnrichmentActivityPref(name: "Jump Rope", durationSec: nil)]
        )
        let apple = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: prefs,
            target: .apple
        )
        XCTAssertEqual(apple.target, .apple)
        // AMA-2371: offer title is device-agnostic ("Rest between sets"); the
        // Open-vs-Lap distinction now lives in `detail`, not the title.
        XCTAssertEqual(apple.offer(.betweenSetRest)?.title, "Rest between sets")
        XCTAssertFalse(
            (apple.offer(.betweenSetRest)?.title ?? "").localizedCaseInsensitiveContains("Lap")
        )
        XCTAssertTrue(
            (apple.offer(.sessionWarmup)?.detail ?? "").contains("until tap")
        )
        XCTAssertFalse(
            (apple.offer(.sessionWarmup)?.detail ?? "").localizedCaseInsensitiveContains("Lap")
        )

        let garmin = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: prefs,
            target: .garmin
        )
        XCTAssertEqual(garmin.offer(.betweenSetRest)?.title, "Rest between sets")
        XCTAssertTrue((garmin.offer(.sessionWarmup)?.detail ?? "").contains("until Lap"))
    }

    func testAppleInitialRestOpenDefaultsTrueWhenUnconfigured() {
        AppleWatchDeliveryPrefsStore.resetForTests()
        XCTAssertTrue(
            WorkoutEnrichmentPushCopy.initialRestOpen(
                standing: .defaults,
                target: .apple
            )
        )
        XCTAssertFalse(
            WorkoutEnrichmentPushCopy.initialRestOpen(
                standing: .defaults,
                target: .garmin
            ),
            "Garmin keeps standing timed default (restOpen false)"
        )
    }

    func testAppleInitialRestOpenStaysOpenEvenWhenDeliveryPrefsTimed() {
        // AMA-2363 — timed delivery prefs must not seed Timed 60s on the sheet.
        AppleWatchDeliveryPrefsStore.resetForTests()
        defer { AppleWatchDeliveryPrefsStore.resetForTests() }

        AppleWatchDeliveryPrefsStore.current = AppleWatchDeliveryPrefs(
            exerciseEnd: .tap,
            restMode: .timed,
            alertsEnabled: false
        )
        XCTAssertTrue(
            WorkoutEnrichmentPushCopy.initialRestOpen(
                standing: .defaults,
                target: .apple
            )
        )

        AppleWatchDeliveryPrefsStore.current = AppleWatchDeliveryPrefs(
            exerciseEnd: .tap,
            restMode: .omit,
            alertsEnabled: false
        )
        XCTAssertFalse(
            WorkoutEnrichmentPushCopy.initialRestOpen(
                standing: .defaults,
                target: .apple
            )
        )
    }

    func testMintMissingExerciseIdsForWarmupSets() {
        let input: [String: Any] = [
            "blocks": [
                [
                    "type": "sets",
                    "exercises": [
                        ["name": "Barbell back squat", "sets": 3, "reps": 10] as [String: Any],
                        [
                            "name": "Bench",
                            "sets": 3,
                            "reps": 8,
                            "exercise_id": "wex_keep"
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ]
        let minted = WorkoutEnrichmentMutations.mintMissingExerciseIds(in: input)
        let exercises = (minted["blocks"] as? [[String: Any]])?.first?["exercises"] as? [[String: Any]]
        let squatId = exercises?.first?["exercise_id"] as? String
        XCTAssertNotNil(squatId)
        XCTAssertTrue(squatId?.hasPrefix("wex_") == true)
        XCTAssertEqual(exercises?.last?["exercise_id"] as? String, "wex_keep")
    }

    func testStripEnrichmentOwnedRemovesSoftAndOrphanJumpRope() {
        let input: [String: Any] = [
            "blocks": [
                [
                    "type": "warmup",
                    "enrichment_kind": "session_warmup",
                    "exercises": [["name": "Jump Rope", "duration_sec": NSNull()]]
                ] as [String: Any],
                // structure-only enrichment soft section (no type) — still stripped
                [
                    "structure": "warmup",
                    "structure_source": "enrichment_default",
                    "exercises": [["name": "Jump Rope"]]
                ] as [String: Any],
                // AMA-2364 leftover: name-only Jump Rope without type=warmup
                [
                    "exercises": [["name": "Jump Rope"]]
                ] as [String: Any],
                // circuit with Jump Rope must not be treated as an orphan
                [
                    "type": "circuit",
                    "exercises": [["name": "Jump Rope"]]
                ] as [String: Any],
                [
                    "type": "sets",
                    "rest_sec": 90,
                    "rest_open": true,
                    "field_provenance": [
                        "rest_sec": "user",
                        "rest_open": "enrichment_default",
                        "notes": "user"
                    ],
                    "exercises": [
                        [
                            "name": "Barbell back squat",
                            "sets": 3,
                            "reps": 10,
                            "exercise_id": "wex_1",
                            "warmup_sets": [
                                ["reps": 8, "structure_source": "enrichment_default"],
                                ["reps": 5, "structure_source": "enrichment_default"]
                            ]
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ]
        let stripped = WorkoutEnrichmentMutations.stripEnrichmentOwned(
            in: input,
            softActivityNames: ["Jump Rope"]
        )
        let blocks = stripped["blocks"] as? [[String: Any]] ?? []
        XCTAssertEqual(blocks.count, 2, String(describing: blocks))
        XCTAssertEqual(blocks[0]["type"] as? String, "circuit")
        let main = blocks[1]
        XCTAssertNil(main["rest_open"])
        XCTAssertEqual(main["rest_sec"] as? Int, 90)
        let prov = main["field_provenance"] as? [String: Any]
        XCTAssertEqual(prov?["rest_sec"] as? String, "user")
        XCTAssertEqual(prov?["notes"] as? String, "user")
        XCTAssertNil(prov?["rest_open"])
        let squat = (main["exercises"] as? [[String: Any]])?.first
        XCTAssertNil(squat?["warmup_sets"])
        XCTAssertEqual(squat?["name"] as? String, "Barbell back squat")
    }

    @MainActor
    func testApplyStripsBeforeEnrichAndRestoreClearsExtras() async {
        let mock = MockAPIService()
        let enrichedBlocks: [String: Any] = [
            "blocks": [
                [
                    "type": "warmup",
                    "enrichment_kind": "session_warmup",
                    "exercises": [["name": "Jump Rope"]]
                ] as [String: Any],
                [
                    "type": "sets",
                    "rest_open": true,
                    "field_provenance": [
                        "rest_sec": "enrichment_default",
                        "rest_open": "enrichment_default"
                    ],
                    "exercises": [
                        [
                            "name": "Barbell back squat",
                            "sets": 3,
                            "reps": 10,
                            "exercise_id": "wex_1",
                            "warmup_sets": [
                                ["reps": 8, "structure_source": "enrichment_default"]
                            ]
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ]
        mock.enrichWorkoutResult = .success(
            EnrichResponse(
                blocksJSON: enrichedBlocks,
                enrichmentApplied: EnrichmentAppliedSummary(
                    prefsSource: "override",
                    added: ["session_warmup", "between_set_rest", "exercise_warmup_sets"]
                )
            )
        )
        var jumpRopePrefs = WorkoutPreferences.defaults
        jumpRopePrefs.sessionWarmup = SessionWarmupPrefs(
            enabled: true,
            activities: [EnrichmentActivityPref(name: "Jump Rope", durationSec: nil)]
        )
        // Pretend prior cancel left an orphan Jump Rope + prior enrich.
        let prior: [String: Any] = [
            "blocks": [
                ["exercises": [["name": "Jump Rope"]]] as [String: Any],
                [
                    "type": "warmup",
                    "enrichment_kind": "session_warmup",
                    "exercises": [["name": "Jump Rope"]]
                ] as [String: Any],
                [
                    "type": "sets",
                    "exercises": [
                        [
                            "name": "Barbell back squat",
                            "sets": 3,
                            "reps": 10,
                            "exercise_id": "wex_1"
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ]
        let softNames = WorkoutEnrichmentPushCoordinator.softActivityNames(from: jumpRopePrefs)
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: WorkoutEnrichmentBlocksJSON.parse(
                WorkoutEnrichmentMutations.stripEnrichmentOwned(
                    in: prior,
                    softActivityNames: softNames
                )
            ).blocks,
            tombstones: [],
            prefs: jumpRopePrefs,
            target: .apple
        )
        let prepared = WorkoutEnrichmentPushCoordinator.Prepared(
            workoutId: "w1",
            title: "Testing",
            plan: plan,
            prefs: jumpRopePrefs,
            tombstones: [],
            blocksJSON: prior,
            target: .apple
        )
        let coordinator = WorkoutEnrichmentPushCoordinator(apiService: mock)
        let outcome = await coordinator.apply(
            prepared: prepared,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.sessionWarmup, .betweenSetRest, .exerciseWarmupSets],
                restOpenOverride: true
            )
        )
        XCTAssertTrue(outcome.allowsAppleHandoff)
        guard let resetBlocks = outcome.resetBlocksJSON else {
            XCTFail("expected reset baseline after apply")
            return
        }
        // Enrich must see a clean baseline — no stacked Jump Rope in the request.
        let sentBlocks = mock.lastEnrichRequest?.blocksJSON["blocks"] as? [[String: Any]] ?? []
        let jumpInRequest = sentBlocks.filter { block in
            ((block["exercises"] as? [[String: Any]]) ?? [])
                .contains { ($0["name"] as? String) == "Jump Rope" }
        }
        XCTAssertEqual(jumpInRequest.count, 0, String(describing: sentBlocks))

        let snapshot = WorkoutEnrichmentPushCoordinator.ResetSnapshot(
            workoutId: "w1",
            title: "Testing",
            blocksJSON: resetBlocks,
            tombstones: outcome.resetTombstones ?? []
        )
        let didRestore = await coordinator.restore(snapshot)
        XCTAssertTrue(didRestore)
        let restored = mock.savedWorkoutBlocksJSON.last?.blocksJSON
        let restoredBlocks = restored?["blocks"] as? [[String: Any]] ?? []
        XCTAssertFalse(
            restoredBlocks.contains { ($0["type"] as? String) == "warmup" },
            String(describing: restoredBlocks)
        )
        XCTAssertFalse(
            restoredBlocks.contains { block in
                ((block["exercises"] as? [[String: Any]]) ?? [])
                    .contains { ($0["name"] as? String) == "Jump Rope" }
            },
            String(describing: restoredBlocks)
        )
    }

    @MainActor
    func testApplyMintsExerciseIdBeforeEnrichRequest() async {
        let mock = MockAPIService()
        mock.enrichWorkoutResult = .success(
            EnrichResponse(
                blocksJSON: ["blocks": []],
                enrichmentApplied: EnrichmentAppliedSummary(
                    prefsSource: "override",
                    added: ["exercise_warmup_sets"]
                )
            )
        )
        let blocksJSON: [String: Any] = [
            "blocks": [
                [
                    "type": "sets",
                    "exercises": [
                        ["name": "Barbell back squat", "sets": 3, "reps": 10] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
        let prepared = WorkoutEnrichmentPushCoordinator.Prepared(
            workoutId: "w1",
            title: "Push",
            plan: plan,
            prefs: .defaults,
            tombstones: [],
            blocksJSON: blocksJSON,
            target: .apple
        )
        let outcome = await WorkoutEnrichmentPushCoordinator(apiService: mock).apply(
            prepared: prepared,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [.exerciseWarmupSets])
        )
        XCTAssertTrue(outcome.allowsAppleHandoff)
        let sent = mock.lastEnrichRequest?.blocksJSON
        let exercises = (sent?["blocks"] as? [[String: Any]])?.first?["exercises"] as? [[String: Any]]
        let id = exercises?.first?["exercise_id"] as? String
        XCTAssertNotNil(id)
        XCTAssertTrue(id?.hasPrefix("wex_") == true)
    }

    @MainActor
    func testApplyMarksIncompleteWhenWarmupSetsSkippedNoIdentity() async {
        let mock = MockAPIService()
        mock.enrichWorkoutResult = .success(
            EnrichResponse(
                blocksJSON: ["blocks": []],
                enrichmentApplied: EnrichmentAppliedSummary(
                    prefsSource: "override",
                    skippedNoIdentity: ["Barbell back squat"]
                )
            )
        )
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
        let prepared = WorkoutEnrichmentPushCoordinator.Prepared(
            workoutId: "w1",
            title: "Push",
            plan: plan,
            prefs: .defaults,
            tombstones: [],
            blocksJSON: ["blocks": []],
            target: .apple
        )
        let outcome = await WorkoutEnrichmentPushCoordinator(apiService: mock).apply(
            prepared: prepared,
            decision: WorkoutEnrichmentPushPlanner.Decision(checkedKinds: [.exerciseWarmupSets])
        )
        XCTAssertTrue(outcome.applied)
        XCTAssertTrue(outcome.enrichFailed)
        XCTAssertFalse(outcome.allowsAppleHandoff)
    }

    func testAppleTimedRestWhenOpenTurnedOff() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.betweenSetRest],
                restSecOverride: 60,
                restOpenOverride: false
            ),
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertTrue(application.prefs.betweenSetRest.enabled)
        XCTAssertFalse(application.prefs.betweenSetRest.restOpen)
        XCTAssertEqual(application.prefs.betweenSetRest.restSec, 60)
    }

    func testAppleOmitRestModeSkipsRestOffer() {
        AppleWatchDeliveryPrefsStore.resetForTests()
        defer { AppleWatchDeliveryPrefsStore.resetForTests() }

        AppleWatchDeliveryPrefsStore.current = AppleWatchDeliveryPrefs(
            exerciseEnd: .tap,
            restMode: .omit,
            alertsEnabled: false
        )
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
        XCTAssertNil(plan.offer(.betweenSetRest))
        XCTAssertFalse(
            WorkoutEnrichmentPushCopy.initialRestOpen(
                standing: .defaults,
                target: .apple
            )
        )
    }

    func testAppleOpenRestApplicationClearsRestSec() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.betweenSetRest],
                restSecOverride: nil,
                restOpenOverride: true
            ),
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertTrue(application.prefs.betweenSetRest.enabled)
        XCTAssertTrue(application.prefs.betweenSetRest.restOpen)
        XCTAssertNil(application.prefs.betweenSetRest.restSec)
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
