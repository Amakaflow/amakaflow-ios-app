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

    func testExistingRestIntentIsNotOffered() {
        let timed = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(blockRestSec: 90)],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(timed.offer(.betweenSetRest))

        let open = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock(blockRestOpen: true)],
            tombstones: [],
            prefs: .defaults
        )
        XCTAssertNil(open.offer(.betweenSetRest))
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

    /// An untouched sheet (no door edits — toggles/rest only) must produce
    /// v1-equivalent prefs: no `per_exercise`, no new excludes.
    func testApplyWithNoDoorEditsStaysV1Equivalent() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [benchBlock()],
            tombstones: [],
            prefs: .defaults
        )
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.sessionWarmup, .betweenSetRest, .exerciseWarmupSets]
            ),
            prefs: .defaults,
            tombstones: []
        )

        XCTAssertEqual(
            application.prefs.sessionWarmup.activities,
            WorkoutPreferences.defaults.sessionWarmup.activities
        )
        XCTAssertNil(application.prefs.exerciseWarmupSets.perExercise)
        XCTAssertEqual(
            application.prefs.exerciseWarmupSets.excludeExerciseKeys,
            WorkoutPreferences.defaults.exerciseWarmupSets.excludeExerciseKeys
        )
        let encoded = try WorkoutEnrichmentJSON.object(from: application.prefs)
        let warmupSets = try XCTUnwrap(encoded["exercise_warmup_sets"] as? [String: Any])
        XCTAssertNil(warmupSets["per_exercise"])
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
