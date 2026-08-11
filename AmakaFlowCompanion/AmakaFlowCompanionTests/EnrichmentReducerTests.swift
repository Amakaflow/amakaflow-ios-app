//
//  EnrichmentReducerTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2408 F2/F3/F4 — opt-in ramps, seed order, round-trip property,
//  reducer action coverage, migration byte-identity.
//

import XCTest
@testable import AmakaFlowCompanion

final class EnrichmentReducerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var readiness: WatchItemReadinessStore!
    private var store: EnrichmentPrefsStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ama2408.tests.\(UUID().uuidString)")!
        readiness = WatchItemReadinessStore(defaults: defaults)
        store = EnrichmentPrefsStore(defaults: defaults, readinessStore: readiness)
    }

    override func tearDown() {
        if let suite = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") {
            _ = suite
        }
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    // MARK: - Opt-in ramps (F2)

    func testRowOnEmptyPerExerciseAppliesZeroRampsAndExcludesAll() throws {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Bench Press", sets: 4, reps: 8),
                    SocialImportExercise(name: "Row", sets: 3, reps: 8),
                    SocialImportExercise(name: "Curl", sets: 3, reps: 10)
                ],
                type: "sets"
            )
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(blocks: blocks, tombstones: [], prefs: .defaults)
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.exerciseWarmupSets],
                perExerciseRamps: []
            ),
            prefs: .defaults,
            tombstones: []
        )

        XCTAssertTrue(application.prefs.exerciseWarmupSets.enabled)
        XCTAssertEqual(application.prefs.exerciseWarmupSets.perExercise, [])
        let excludes = Set(application.prefs.exerciseWarmupSets.excludeExerciseKeys)
        XCTAssertTrue(excludes.contains("bench press"))
        XCTAssertTrue(excludes.contains("row"))
        XCTAssertTrue(excludes.contains("curl"))
        XCTAssertEqual(
            LegacyOptInRampMigration.optInEffectiveRamps(
                prefs: application.prefs.exerciseWarmupSets,
                candidateNames: ["Bench Press", "Row", "Curl"]
            ),
            [:]
        )
    }

    func testOnlyExplicitlyEnabledReceiveRamps() throws {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Bench Press", sets: 4, reps: 8),
                    SocialImportExercise(name: "Row", sets: 3, reps: 8),
                    SocialImportExercise(name: "Curl", sets: 3, reps: 10)
                ],
                type: "sets"
            )
        ]
        let plan = WorkoutEnrichmentPushPlanner.plan(blocks: blocks, tombstones: [], prefs: .defaults)
        let enabled = PerExerciseRamp(
            exerciseRef: "Bench Press",
            enabled: true,
            sets: [try RampSet(kind: .reps, value: 8), try RampSet(kind: .reps, value: 5)]
        )
        let disabled = PerExerciseRamp(exerciseRef: "Row", enabled: false, sets: [])
        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: WorkoutEnrichmentPushPlanner.Decision(
                checkedKinds: [.exerciseWarmupSets],
                perExerciseRamps: [enabled, disabled]
            ),
            prefs: .defaults,
            tombstones: []
        )

        let effective = LegacyOptInRampMigration.optInEffectiveRamps(
            prefs: application.prefs.exerciseWarmupSets,
            candidateNames: ["Bench Press", "Row", "Curl"]
        )
        XCTAssertEqual(Set(effective.keys), ["bench press"])
        XCTAssertTrue(application.prefs.exerciseWarmupSets.excludeExerciseKeys.contains("row"))
        XCTAssertTrue(application.prefs.exerciseWarmupSets.excludeExerciseKeys.contains("curl"))
    }

    func testMigrationByteIdenticalEffectiveRamps() {
        let candidates = ["Incline Smith", "Row", "Curl", "Press"]
        let legacy = ExerciseWarmupSetsPrefs(
            enabled: true,
            defaultSets: [WarmupSetDefault(reps: 8), WarmupSetDefault(reps: 5)],
            excludeExerciseKeys: ["curl"],
            perExercise: nil
        )
        let before = LegacyOptInRampMigration.legacyEffectiveRamps(
            prefs: legacy,
            candidateNames: candidates
        )
        let migrated = LegacyOptInRampMigration.materialize(
            prefs: legacy,
            candidateNames: candidates
        )
        let after = LegacyOptInRampMigration.optInEffectiveRamps(
            prefs: migrated,
            candidateNames: candidates
        )
        XCTAssertEqual(before.keys.sorted(), after.keys.sorted())
        for key in before.keys {
            XCTAssertEqual(before[key]?.map(\.kind), after[key]?.map(\.kind))
            XCTAssertEqual(before[key]?.map(\.value), after[key]?.map(\.value))
        }
        // Curl excluded before and after.
        XCTAssertNil(after["curl"])
    }

    func testApplyRampToAllCopiesEnabledOnly() throws {
        let sets = [try RampSet(kind: .reps, value: 10)]
        var state = baseState(candidates: ["A", "B", "C"])
        state.perExerciseRamps = [
            PerExerciseRamp(exerciseRef: "A", enabled: true, sets: [try RampSet(kind: .reps, value: 3)]),
            PerExerciseRamp(exerciseRef: "B", enabled: true, sets: [try RampSet(kind: .reps, value: 4)]),
            PerExerciseRamp(exerciseRef: "C", enabled: false, sets: [try RampSet(kind: .reps, value: 12)])
        ]
        state = EnrichmentReducer.reduce(state, .applyRampToAll(sets: sets))
        XCTAssertEqual(state.perExerciseRamps[0].sets, sets)
        XCTAssertEqual(state.perExerciseRamps[1].sets, sets)
        XCTAssertEqual(state.perExerciseRamps[2].sets.map(\.value), [12])
        // Independently editable afterward.
        state = EnrichmentReducer.reduce(
            state,
            .setRamp(
                exercise: "A",
                ramp: PerExerciseRamp(
                    exerciseRef: "A",
                    enabled: true,
                    sets: [try RampSet(kind: .reps, value: 99)]
                )
            )
        )
        XCTAssertEqual(state.perExerciseRamps[0].sets.map(\.value), [99])
        XCTAssertEqual(state.perExerciseRamps[1].sets, sets)
    }

    // MARK: - Seed order (F3)

    func testSeedWorkoutPrefsWinOverGlobals() throws {
        let globals = WorkoutPreferences.defaults
        let saved = EnrichmentState.Persisted(
            checkedKinds: [.exerciseWarmupSets],
            mobilityActivities: [EnrichmentActivityPref(name: "Saved Mobility", durationSec: 60)],
            cooldownActivities: [EnrichmentActivityPref(name: "Saved Cool", durationSec: 90)],
            perExerciseRamps: [
                PerExerciseRamp(
                    exerciseRef: "Bench",
                    enabled: true,
                    sets: [try RampSet(kind: .reps, value: 3)]
                )
            ],
            restOpen: true,
            restSec: 45
        )
        let state = EnrichmentState.seed(
            workoutPrefs: saved,
            globalDefaults: globals,
            defaultCheckedKinds: [.sessionWarmup, .betweenSetRest, .exerciseWarmupSets],
            candidateExerciseNames: ["Bench", "Row"],
            target: .garmin
        )
        XCTAssertEqual(state.checkedKinds, [.exerciseWarmupSets])
        XCTAssertEqual(state.mobilityActivities.first?.name, "Saved Mobility")
        XCTAssertEqual(state.perExerciseRamps.first?.sets.first?.value, 3)
        XCTAssertTrue(state.restOpen)
    }

    func testSeedGlobalsOnlyWhenAbsent() {
        let state = EnrichmentState.seed(
            workoutPrefs: nil,
            globalDefaults: .defaults,
            defaultCheckedKinds: [.sessionWarmup, .betweenSetRest],
            candidateExerciseNames: ["Bench"],
            target: .apple
        )
        XCTAssertEqual(state.checkedKinds, [.sessionWarmup, .betweenSetRest])
        XCTAssertEqual(
            state.mobilityActivities,
            WorkoutPreferences.defaults.sessionWarmup.activities
        )
        XCTAssertTrue(state.perExerciseRamps.isEmpty)
    }

    func testLateAddedExerciseAppearsUnchecked() throws {
        let saved = EnrichmentState.Persisted(
            checkedKinds: [.exerciseWarmupSets],
            mobilityActivities: [],
            cooldownActivities: [],
            perExerciseRamps: [
                PerExerciseRamp(
                    exerciseRef: "Bench",
                    enabled: true,
                    sets: [try RampSet(kind: .reps, value: 8)]
                )
            ],
            restOpen: false,
            restSec: 60
        )
        let state = EnrichmentState.seed(
            workoutPrefs: saved,
            globalDefaults: .defaults,
            defaultCheckedKinds: [.exerciseWarmupSets],
            candidateExerciseNames: ["Bench", "New Fly"],
            target: .garmin
        )
        let enabled = EnrichmentRowSummary.enabledRamps(
            in: state.perExerciseRamps,
            candidates: state.candidateExerciseNames
        )
        XCTAssertEqual(enabled.map { ExerciseKeyNormalizer.normalize($0.exerciseRef) }, ["bench"])
        XCTAssertFalse(state.perExerciseRamps.contains {
            ExerciseKeyNormalizer.normalize($0.exerciseRef) == "new fly"
        })
    }

    // MARK: - Round-trip property (F4) — real UserDefaults store

    func testRoundTripConfirmPersistReopenIdentical() throws {
        let workoutID = "w-roundtrip-\(UUID().uuidString)"
        let candidates = ["Incline Smith", "Row", "Curl", "Press"]
        var state = EnrichmentState.seed(
            workoutPrefs: nil,
            globalDefaults: .defaults,
            defaultCheckedKinds: [.sessionWarmup, .exerciseWarmupSets, .betweenSetRest],
            candidateExerciseNames: candidates,
            target: .garmin
        )

        let actions: [EnrichmentAction] = [
            .toggleExercise("Incline Smith"),
            .toggleExercise("Row"),
            .setSequence(.cooldown, [
                EnrichmentActivityPref(name: "Stretch flow", durationSec: 180),
                EnrichmentActivityPref(name: "Treadmill", durationSec: nil)
            ]),
            // OFF but configured cooldown retained.
            .toggleRow(.cooldown), // turn ON then OFF
            .toggleRow(.cooldown),
            .setRest(open: false, sec: 90),
            .confirm
        ]
        let reduced = EnrichmentReducer.reduce(state, actions: actions)
        store.save(workoutID: workoutID, prefs: reduced.persisted())

        let reloaded = store.load(workoutID: workoutID)
        let reopened = EnrichmentState.seed(
            workoutPrefs: reloaded,
            globalDefaults: .defaults,
            defaultCheckedKinds: [.sessionWarmup],
            candidateExerciseNames: candidates,
            target: .garmin
        )

        XCTAssertEqual(reopened.checkedKinds, reduced.checkedKinds)
        XCTAssertEqual(reopened.perExerciseRamps, reduced.perExerciseRamps)
        XCTAssertEqual(reopened.mobilityActivities, reduced.mobilityActivities)
        XCTAssertEqual(reopened.cooldownActivities, reduced.cooldownActivities)
        XCTAssertEqual(reopened.restOpen, reduced.restOpen)
        XCTAssertEqual(reopened.restSec, reduced.restSec)
        // OFF-but-configured cooldown retained.
        XCTAssertFalse(reopened.checkedKinds.contains(.cooldown))
        XCTAssertFalse(reopened.cooldownActivities.isEmpty)
    }

    // MARK: - Reducer action coverage

    func testReducerToggleRow() {
        var state = baseState(candidates: ["A"])
        state = EnrichmentReducer.reduce(state, .toggleRow(.cooldown))
        XCTAssertTrue(state.checkedKinds.contains(.cooldown))
        state = EnrichmentReducer.reduce(state, .toggleRow(.cooldown))
        XCTAssertFalse(state.checkedKinds.contains(.cooldown))
    }

    func testReducerToggleExerciseSeedsDefaultRamp() {
        var state = baseState(candidates: ["Bench"])
        state = EnrichmentReducer.reduce(state, .toggleExercise("Bench"))
        XCTAssertEqual(state.perExerciseRamps.count, 1)
        XCTAssertTrue(state.perExerciseRamps[0].enabled)
        XCTAssertEqual(state.perExerciseRamps[0].sets.map(\.value), [8, 5])
    }

    func testReducerSetSequenceAndRestAndSkipConfirm() {
        var state = baseState(candidates: ["A"])
        let steps = [EnrichmentActivityPref(name: "Ski", durationSec: 60)]
        state = EnrichmentReducer.reduce(state, .setSequence(.mobility, steps))
        XCTAssertEqual(state.mobilityActivities, steps)
        state = EnrichmentReducer.reduce(state, .setRest(open: true, sec: 999))
        XCTAssertTrue(state.restOpen)
        XCTAssertEqual(state.restSec, 300) // clamped
        let before = state
        state = EnrichmentReducer.reduce(state, .confirm)
        XCTAssertEqual(state, before)
        state = EnrichmentReducer.reduce(state, .skip)
        XCTAssertEqual(state, before)
    }

    func testWatchItemSummaryRoutesThroughEnrichmentRowSummary() throws {
        // Assert the single call-site contract: building state → summary(for:)
        // matches EnrichmentRowSummary directly (WatchItemViewModel.summary uses this).
        let ramp = PerExerciseRamp(
            exerciseRef: "Incline Smith",
            enabled: true,
            sets: [try RampSet(kind: .reps, value: 8), try RampSet(kind: .reps, value: 5)]
        )
        let state = EnrichmentState(
            checkedKinds: [.exerciseWarmupSets],
            mobilityActivities: [],
            cooldownActivities: [],
            perExerciseRamps: [ramp],
            restOpen: false,
            restSec: 60,
            candidateExerciseNames: Array((0..<7).map { $0 == 0 ? "Incline Smith" : "Ex\($0)" }),
            target: .garmin
        )
        XCTAssertEqual(
            state.summary(for: .warmups),
            EnrichmentRowSummary.warmups(
                isOn: true,
                candidateNames: state.candidateExerciseNames,
                ramps: state.perExerciseRamps
            )
        )
        XCTAssertNil(state.summary(for: WatchItemReadinessRow.cooldown))
    }

    // MARK: - Helpers

    private func baseState(candidates: [String]) -> EnrichmentState {
        EnrichmentState(
            checkedKinds: [.exerciseWarmupSets],
            mobilityActivities: [],
            cooldownActivities: [],
            perExerciseRamps: [],
            restOpen: false,
            restSec: 60,
            candidateExerciseNames: candidates,
            target: .garmin
        )
    }
}
