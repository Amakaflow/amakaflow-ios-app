//
//  WorkoutEnrichmentModelsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2336: declared enrichment contract — unknown-tolerant provenance, tombstones,
//  quick-add provenance, rest intent validity (spec 2026-07-27 §§1–2, §5).
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutEnrichmentModelsTests: XCTestCase {
    // MARK: - Unknown-tolerant provenance

    func testUnknownStructureSourceDecodesToUnknown() throws {
        let data = Data(#"{"structure_source": "invented_by_a_newer_backend"}"#.utf8)
        let decoded = try JSONDecoder().decode(SourceProbe.self, from: data)
        XCTAssertEqual(decoded.structureSource, .unknown)
    }

    func testUnknownProvSourceDecodesToUnknown() throws {
        let data = Data(#"{"prov": "future_value"}"#.utf8)
        let decoded = try JSONDecoder().decode(ProvProbe.self, from: data)
        XCTAssertEqual(decoded.prov, .unknown)
    }

    func testKnownProvenanceLiteralsRoundTrip() throws {
        XCTAssertEqual(StructureSource.userAdded.rawValue, "user_added")
        XCTAssertEqual(StructureSource.enrichmentDefault.rawValue, "enrichment_default")
        XCTAssertEqual(StructureSource.userNote.rawValue, "user_note")
        XCTAssertEqual(ProvSource.enrichmentDefault.rawValue, "enrichment_default")
        XCTAssertEqual(ProvSource.user.rawValue, "user")

        for source in [StructureSource.userAdded, .enrichmentDefault, .userNote] {
            let row = WarmupSetRow(reps: 8, structureSource: source)
            let data = try WorkoutEnrichmentJSON.encoder.encode(row)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["structure_source"] as? String, source.rawValue)
            let decoded = try WorkoutEnrichmentJSON.decoder.decode(WarmupSetRow.self, from: data)
            XCTAssertEqual(decoded, row)
        }
    }

    func testWarmupSetRowDefaultsToEnrichmentDefaultOnDecode() throws {
        let data = Data(#"{"reps": 5}"#.utf8)
        let row = try WorkoutEnrichmentJSON.decoder.decode(WarmupSetRow.self, from: data)
        XCTAssertEqual(row.reps, 5)
        XCTAssertEqual(row.structureSource, .enrichmentDefault)
    }

    func testActivityWithUnknownProvenanceDoesNotThrow() throws {
        let data = Data(#"{"name": "Ski Erg", "duration_sec": null, "structure_source": "wat"}"#.utf8)
        let activity = try WorkoutEnrichmentJSON.decoder.decode(EnrichmentActivity.self, from: data)
        XCTAssertEqual(activity.name, "Ski Erg")
        XCTAssertNil(activity.durationSec)
        XCTAssertEqual(activity.structureSource, .unknown)
    }

    // MARK: - Prefs + rest validity

    func testDefaultPrefsMatchBackendDefaults() {
        let prefs = WorkoutPreferences.defaults
        XCTAssertTrue(prefs.sessionWarmup.enabled)
        XCTAssertEqual(prefs.sessionWarmup.activities.map(\.name), ["Jump Rope"])
        XCTAssertNil(prefs.sessionWarmup.activities.first?.durationSec)
        XCTAssertNil(prefs.sessionWarmup.activities.first?.goal)
        XCTAssertFalse(prefs.cooldown.enabled)
        XCTAssertTrue(prefs.cooldown.activities.isEmpty)
        XCTAssertTrue(prefs.betweenSetRest.enabled)
        XCTAssertEqual(prefs.betweenSetRest.restSec, 60)
        XCTAssertFalse(prefs.betweenSetRest.restOpen)
        XCTAssertTrue(prefs.exerciseWarmupSets.enabled)
        XCTAssertEqual(prefs.exerciseWarmupSets.defaultSets.map(\.reps), [8, 5])
        XCTAssertTrue(prefs.exerciseWarmupSets.excludeExerciseKeys.isEmpty)
        // AMA-2378 — untouched defaults stay byte-compatible with v1 (no per-exercise ramps).
        XCTAssertNil(prefs.exerciseWarmupSets.perExercise)
    }

    // MARK: - AMA-2378: soft goals (ActivityGoal / SessionActivity.goal)

    func testActivityGoalRoundTripsAllKinds() throws {
        let cases: [(ActivityGoalKind, Int?)] = [
            (.time, 300),
            (.distance, 1000),
            (.cals, 50),
            (.open, nil)
        ]
        for (kind, value) in cases {
            let goal = try ActivityGoal(kind: kind, value: value)
            let data = try WorkoutEnrichmentJSON.encoder.encode(goal)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["kind"] as? String, kind.rawValue)
            if let value {
                XCTAssertEqual(object["value"] as? Int, value)
            } else {
                XCTAssertNil(object["value"])
            }
            let decoded = try WorkoutEnrichmentJSON.decoder.decode(ActivityGoal.self, from: data)
            XCTAssertEqual(decoded, goal)
        }
    }

    func testActivityGoalTimedDistanceCalsRequireValue() {
        for kind in [ActivityGoalKind.time, .distance, .cals] {
            XCTAssertThrowsError(try ActivityGoal(kind: kind, value: nil)) { error in
                XCTAssertEqual(error as? WorkoutPreferencesValidationError, .activityGoalRequiresValue)
            }
            let data = Data("{\"kind\": \"\(kind.rawValue)\"}".utf8)
            XCTAssertThrowsError(try WorkoutEnrichmentJSON.decoder.decode(ActivityGoal.self, from: data))
        }
    }

    func testActivityGoalOpenRejectsValue() {
        XCTAssertThrowsError(try ActivityGoal(kind: .open, value: 60)) { error in
            XCTAssertEqual(error as? WorkoutPreferencesValidationError, .activityGoalOpenWithValue)
        }
        let data = Data(#"{"kind": "open", "value": 60}"#.utf8)
        XCTAssertThrowsError(try WorkoutEnrichmentJSON.decoder.decode(ActivityGoal.self, from: data))
    }

    func testEnrichmentActivityPrefCarriesGoalAndEqualityIncludesIt() throws {
        let goal = try ActivityGoal(kind: .distance, value: 1000)
        let withGoal = EnrichmentActivityPref(name: "Row", goal: goal)
        let withoutGoal = EnrichmentActivityPref(name: "Row")
        XCTAssertNotEqual(withGoal, withoutGoal)

        let object = try WorkoutEnrichmentJSON.object(from: withGoal)
        let encodedGoal = try XCTUnwrap(object["goal"] as? [String: Any])
        XCTAssertEqual(encodedGoal["kind"] as? String, "distance")
        XCTAssertEqual(encodedGoal["value"] as? Int, 1000)
        XCTAssertNil(object["duration_sec"])

        let roundTripData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try WorkoutEnrichmentJSON.decoder.decode(EnrichmentActivityPref.self, from: roundTripData)
        XCTAssertEqual(decoded.goal, goal)
    }

    func testEnrichmentActivityBlockCarriesGoalFromPref() throws {
        let goal = try ActivityGoal(kind: .open, value: nil)
        let pref = EnrichmentActivityPref(name: "Jump Rope", goal: goal)
        let activity = EnrichmentActivity(pref: pref)
        XCTAssertEqual(activity.goal, goal)

        let data = Data(#"{"name": "Row", "duration_sec": 300, "goal": {"kind": "time", "value": 300}}"#.utf8)
        let decoded = try WorkoutEnrichmentJSON.decoder.decode(EnrichmentActivity.self, from: data)
        XCTAssertEqual(decoded.goal, try ActivityGoal(kind: .time, value: 300))
        XCTAssertEqual(decoded.structureSource, .enrichmentDefault)
    }

    // MARK: - AMA-2378: per-exercise ramps (RampSet / PerExerciseRamp / WarmupSetRow)

    func testRampSetRoundTripsAllKinds() throws {
        let cases: [(WarmupSetKind, Int?)] = [
            (.reps, 10),
            (.time, 30),
            (.cals, 15),
            (.open, nil)
        ]
        for (kind, value) in cases {
            let set = try RampSet(kind: kind, value: value, intensityNote: "easy")
            let data = try WorkoutEnrichmentJSON.encoder.encode(set)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["kind"] as? String, kind.rawValue)
            XCTAssertEqual(object["intensity_note"] as? String, "easy")
            if let value {
                XCTAssertEqual(object["value"] as? Int, value)
            } else {
                XCTAssertNil(object["value"])
            }
            let decoded = try WorkoutEnrichmentJSON.decoder.decode(RampSet.self, from: data)
            XCTAssertEqual(decoded, set)
        }
    }

    func testRampSetOpenHasNoValue() throws {
        let open = try RampSet(kind: .open, value: nil)
        XCTAssertNil(open.value)
        XCTAssertThrowsError(try RampSet(kind: .open, value: 5)) { error in
            XCTAssertEqual(error as? WorkoutPreferencesValidationError, .rampSetOpenWithValue)
        }
        XCTAssertThrowsError(try RampSet(kind: .time, value: nil)) { error in
            XCTAssertEqual(error as? WorkoutPreferencesValidationError, .rampSetRequiresValue)
        }
    }

    func testPerExerciseRampRoundTrips() throws {
        let ramp = PerExerciseRamp(
            exerciseRef: "wex_abc",
            enabled: true,
            sets: [
                try RampSet(kind: .reps, value: 12),
                try RampSet(kind: .open, value: nil, intensityNote: "light")
            ]
        )
        let object = try WorkoutEnrichmentJSON.object(from: ramp)
        XCTAssertEqual(object["exercise_ref"] as? String, "wex_abc")
        XCTAssertEqual(object["enabled"] as? Bool, true)
        let sets = try XCTUnwrap(object["sets"] as? [[String: Any]])
        XCTAssertEqual(sets.count, 2)

        let roundTripData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try WorkoutEnrichmentJSON.decoder.decode(PerExerciseRamp.self, from: roundTripData)
        XCTAssertEqual(decoded.exerciseRef, ramp.exerciseRef)
        XCTAssertEqual(decoded.enabled, ramp.enabled)
        XCTAssertEqual(decoded.sets, ramp.sets)
        XCTAssertEqual(decoded, ramp)
    }

    func testExerciseWarmupSetsPrefsPerExerciseRoundTrip() throws {
        var prefs = ExerciseWarmupSetsPrefs.defaults
        prefs.perExercise = [
            PerExerciseRamp(exerciseRef: "wex_abc", sets: [try RampSet(kind: .reps, value: 10)])
        ]
        let object = try WorkoutEnrichmentJSON.object(from: prefs)
        let perExercise = try XCTUnwrap(object["per_exercise"] as? [[String: Any]])
        XCTAssertEqual(perExercise.count, 1)

        let roundTripData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try WorkoutEnrichmentJSON.decoder.decode(ExerciseWarmupSetsPrefs.self, from: roundTripData)
        XCTAssertEqual(decoded.perExercise?.first?.exerciseRef, "wex_abc")

        // Untouched (no per_exercise key) decodes to nil — v1 shape stays byte-compatible.
        let legacy = try WorkoutEnrichmentJSON.decoder.decode(
            ExerciseWarmupSetsPrefs.self,
            from: Data(#"{"enabled": true, "default_sets": [{"reps": 8}]}"#.utf8)
        )
        XCTAssertNil(legacy.perExercise)
    }

    // MARK: - AMA-2378 Task 5: warm-up pick + ramp editor pure helpers

    /// The seeded default mirrors the backend design spec's own example ramp
    /// (8·5 reps with `LIGHT · ~40%` / `MODERATE · ~60%` intensity notes).
    func testDefaultRampSetsMatchesGlobalEightFiveWithIntensityNotes() {
        let sets = WorkoutEnrichmentMutations.defaultRampSets()
        XCTAssertEqual(sets.map(\.kind), [.reps, .reps])
        XCTAssertEqual(sets.map(\.value), [8, 5])
        XCTAssertEqual(sets.first?.intensityNote, "LIGHT · ~40%")
        XCTAssertEqual(sets.last?.intensityNote, "MODERATE · ~60%")
    }

    /// Core isolation guarantee for "Apply this ramp to all selected": every
    /// enabled ramp receives its own copy of the source sets, disabled ramps
    /// are untouched, and mutating one exercise's sets afterward never
    /// reaches through to another's — the pure half of Task 5's apply-to-all.
    func testApplyRampSetsCopiesThenDiverge() throws {
        let sourceSets = [
            try RampSet(kind: .reps, value: 10, intensityNote: "custom"),
            try RampSet(kind: .open, value: nil)
        ]
        var ramps = [
            PerExerciseRamp(exerciseRef: "deadlift", enabled: true, sets: sourceSets),
            PerExerciseRamp(exerciseRef: "overhead press", enabled: true, sets: [try RampSet(kind: .reps, value: 3)]),
            PerExerciseRamp(exerciseRef: "leg press", enabled: false, sets: [try RampSet(kind: .reps, value: 12)])
        ]

        ramps = WorkoutEnrichmentMutations.applyRampSets(sourceSets, toEnabledRampsIn: ramps)

        XCTAssertEqual(ramps[0].sets, sourceSets)
        XCTAssertEqual(ramps[1].sets, sourceSets)
        // Disabled ramp is untouched — apply-to-all only reaches enabled exercises.
        XCTAssertEqual(ramps[2].sets, [try RampSet(kind: .reps, value: 12)])

        // Diverge: mutating exercise A's copy after the apply must not move B's.
        ramps[0].sets[0] = try RampSet(kind: .cals, value: 20)
        XCTAssertEqual(ramps[1].sets, sourceSets, "mutating A's sets must never mutate B's independent copy")
        XCTAssertNotEqual(ramps[0].sets, ramps[1].sets)
    }

    /// Applying with no enabled ramps at all is a safe no-op — never crashes,
    /// never mutates a disabled entry.
    func testApplyRampSetsNoEnabledRampsIsNoOp() throws {
        let disabledOnly = [
            PerExerciseRamp(exerciseRef: "a", enabled: false, sets: [try RampSet(kind: .reps, value: 1)]),
            PerExerciseRamp(exerciseRef: "b", enabled: false, sets: [])
        ]
        let result = WorkoutEnrichmentMutations.applyRampSets(
            [try RampSet(kind: .reps, value: 9)],
            toEnabledRampsIn: disabledOnly
        )
        XCTAssertEqual(result, disabledOnly)
    }

    func testWarmupSetRowKindAndValueWithoutReps() throws {
        let data = Data(#"{"kind": "time", "value": 30, "intensity_note": "hard"}"#.utf8)
        let row = try WorkoutEnrichmentJSON.decoder.decode(WarmupSetRow.self, from: data)
        XCTAssertNil(row.reps)
        XCTAssertEqual(row.kind, .time)
        XCTAssertEqual(row.value, 30)
        XCTAssertEqual(row.intensityNote, "hard")
        XCTAssertEqual(row.structureSource, .enrichmentDefault)

        let object = try WorkoutEnrichmentJSON.object(from: row)
        XCTAssertNil(object["reps"])
        XCTAssertEqual(object["kind"] as? String, "time")
        XCTAssertEqual(object["value"] as? Int, 30)
    }

    func testWarmupSetRowOpenKindHasNoValue() throws {
        let data = Data(#"{"kind": "open"}"#.utf8)
        let row = try WorkoutEnrichmentJSON.decoder.decode(WarmupSetRow.self, from: data)
        XCTAssertEqual(row.kind, .open)
        XCTAssertNil(row.value)
        XCTAssertNil(row.reps)
    }

    func testWarmupSetRowStillDecodesRepsOnly() throws {
        let data = Data(#"{"reps": 5}"#.utf8)
        let row = try WorkoutEnrichmentJSON.decoder.decode(WarmupSetRow.self, from: data)
        XCTAssertEqual(row.reps, 5)
        XCTAssertNil(row.kind)
        XCTAssertEqual(row.structureSource, .enrichmentDefault)
    }

    func testWarmupSetRowRequiresRepsOrKind() {
        let data = Data(#"{"weight": 10}"#.utf8)
        XCTAssertThrowsError(try WorkoutEnrichmentJSON.decoder.decode(WarmupSetRow.self, from: data)) { error in
            XCTAssertEqual(error as? WorkoutPreferencesValidationError, .warmupSetRowRequiresRepsOrKind)
        }
    }

    func testWarmupSetRowParseListHandlesRepsAndKindRows() {
        let rows = WarmupSetRow.parseList([
            ["reps": 8],
            ["kind": "time", "value": 30],
            ["kind": "open"],
            ["weight": 10]
        ])
        XCTAssertEqual(rows?.count, 3)
        XCTAssertEqual(rows?[0].reps, 8)
        XCTAssertEqual(rows?[1].kind, .time)
        XCTAssertEqual(rows?[1].value, 30)
        XCTAssertEqual(rows?[2].kind, .open)
        XCTAssertNil(rows?[2].value)
    }

    func testPrefsEncodeSnakeCaseKeys() throws {
        let object = try WorkoutEnrichmentJSON.object(from: WorkoutPreferences.defaults)
        XCTAssertNotNil(object["session_warmup"])
        XCTAssertNotNil(object["between_set_rest"])
        XCTAssertNotNil(object["exercise_warmup_sets"])
        let rest = try XCTUnwrap(object["between_set_rest"] as? [String: Any])
        XCTAssertEqual(rest["rest_sec"] as? Int, 60)
        XCTAssertEqual(rest["rest_open"] as? Bool, false)
        let warmup = try XCTUnwrap(object["session_warmup"] as? [String: Any])
        let activities = try XCTUnwrap(warmup["activities"] as? [[String: Any]])
        // Prefs activities carry no structure_source — backend forbids extra keys.
        XCTAssertNil(activities.first?["structure_source"])
    }

    func testRestOpenWithRestSecIsRejected() {
        XCTAssertThrowsError(try BetweenSetRestPrefs(enabled: true, restSec: 60, restOpen: true)) { error in
            XCTAssertEqual(error as? WorkoutPreferencesValidationError, .restOpenWithRestSec)
        }
        XCTAssertThrowsError(
            try WorkoutEnrichmentMutations.validatedRest(restSec: 60, restOpen: true)
        ) { error in
            XCTAssertEqual(error as? WorkoutPreferencesValidationError, .restOpenWithRestSec)
        }
    }

    func testRestOpenWithRestSecIsRejectedOnDecode() {
        let data = Data(#"{"enabled": true, "rest_sec": 45, "rest_open": true}"#.utf8)
        XCTAssertThrowsError(try WorkoutEnrichmentJSON.decoder.decode(BetweenSetRestPrefs.self, from: data))
    }

    func testValidRestIntentShapes() throws {
        let timed = try BetweenSetRestPrefs(enabled: true, restSec: 90, restOpen: false)
        XCTAssertEqual(timed.restSec, 90)
        let open = try BetweenSetRestPrefs(enabled: true, restSec: nil, restOpen: true)
        XCTAssertNil(open.restSec)
        XCTAssertTrue(open.restOpen)
        let skipped = try BetweenSetRestPrefs(enabled: false, restSec: nil, restOpen: false)
        XCTAssertNil(skipped.restSec)
        XCTAssertFalse(skipped.restOpen)
    }

    // MARK: - Presence by type + tombstones

    func testPresenceIsTestedByTypeNotProvenance() {
        let sourceWarmup = SocialImportBlock(
            label: "Warm-up",
            rounds: 1,
            exercises: [SocialImportExercise(name: "Row 500m")],
            type: StructureBlockType.warmup.rawValue,
            structureSource: StructureSource.explicit.rawValue
        )
        XCTAssertTrue(WorkoutEnrichmentPresence.hasWarmupBlock(in: [sourceWarmup]))
        XCTAssertFalse(WorkoutEnrichmentPresence.hasCooldownBlock(in: [sourceWarmup]))

        let cooldown = SocialImportBlock(
            label: "Cooldown",
            rounds: 1,
            exercises: [SocialImportExercise(name: "Walk")],
            type: StructureBlockType.cooldown.rawValue
        )
        XCTAssertTrue(WorkoutEnrichmentPresence.hasCooldownBlock(in: [cooldown]))
    }

    func testKindTombstoneIgnoresExerciseScopedEntries() {
        let tombstones = [
            EnrichmentTombstone(kind: .sessionWarmup),
            EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_1")
        ]
        XCTAssertTrue(WorkoutEnrichmentPresence.isTombstoned(.sessionWarmup, tombstones: tombstones))
        XCTAssertFalse(WorkoutEnrichmentPresence.isTombstoned(.cooldown, tombstones: tombstones))
        XCTAssertTrue(
            WorkoutEnrichmentPresence.isTombstoned(
                .exerciseWarmupSets,
                exerciseId: "wex_1",
                tombstones: tombstones
            )
        )
        XCTAssertFalse(
            WorkoutEnrichmentPresence.isTombstoned(
                .exerciseWarmupSets,
                exerciseId: "wex_2",
                tombstones: tombstones
            )
        )
    }

    func testTombstoneMutationsAreIdempotentAndClearable() {
        var list: [EnrichmentTombstone] = []
        WorkoutEnrichmentMutations.appendTombstone(&list, kind: .cooldown)
        WorkoutEnrichmentMutations.appendTombstone(&list, kind: .cooldown)
        XCTAssertEqual(list.count, 1)
        // Per-exercise tombstones without an id are rejected by the backend — never written.
        WorkoutEnrichmentMutations.appendTombstone(&list, kind: .exerciseWarmupSets)
        XCTAssertEqual(list.count, 1)
        WorkoutEnrichmentMutations.clearTombstone(&list, kind: .cooldown)
        XCTAssertTrue(list.isEmpty)
    }

    func testTombstoneEncodesSnakeCaseAndOmitsNilExerciseId() throws {
        let object = try WorkoutEnrichmentJSON.object(from: EnrichmentTombstone(kind: .betweenSetRest))
        XCTAssertEqual(object["kind"] as? String, "between_set_rest")
        XCTAssertNil(object["exercise_id"])

        let scoped = try WorkoutEnrichmentJSON.object(
            from: EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_abc")
        )
        XCTAssertEqual(scoped["exercise_id"] as? String, "wex_abc")
    }

    func testMintedExerciseIdIsPrefixedAndUnique() {
        let first = WorkoutEnrichmentMutations.mintExerciseId()
        let second = WorkoutEnrichmentMutations.mintExerciseId()
        XCTAssertTrue(first.hasPrefix("wex_"))
        XCTAssertFalse(first.contains("-"))
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Name key normalization

    func testExerciseKeyNormalization() {
        XCTAssertEqual(ExerciseKeyNormalizer.normalize("  Bench   Press "), "bench press")
        XCTAssertEqual(ExerciseKeyNormalizer.normalize("BENCH\tPRESS"), "bench press")
        XCTAssertEqual(ExerciseKeyNormalizer.normalize("Ｂench Press"), "bench press")
    }

    // MARK: - Editor quick add / delete provenance

    func testQuickAddSessionWarmupStampsEnrichmentDefault() throws {
        var session = EditorV2Session(title: "Push")
        session.addExercise(named: "Bench Press")

        XCTAssertTrue(session.quickAddSessionWarmup(from: .defaults))
        let warmupGroup = try XCTUnwrap(session.groups.values.first { $0.type == .warmup })
        XCTAssertEqual(warmupGroup.structureSource, .enrichmentDefault)
        XCTAssertEqual(warmupGroup.enrichmentKind, .sessionWarmup)
        XCTAssertEqual(session.exercises.first?.name, "Jump Rope")
        XCTAssertEqual(session.exercises.first?.structureSource, .enrichmentDefault)
        XCTAssertNil(session.exercises.first?.durationSeconds)
    }

    func testQuickAddSessionWarmupNoOpsWhenWarmupTypeAlreadyPresent() {
        var session = EditorV2Session(title: "Push")
        let key = "existing-warmup"
        session.groups[key] = EditorV2Group(
            id: key,
            type: .warmup,
            name: "Warm-up",
            structureSource: .explicit
        )
        session.exercises = [EditorV2Exercise(name: "Row 500m", durationSeconds: 300, groupKey: key)]

        XCTAssertFalse(session.quickAddSessionWarmup(from: .defaults))
        XCTAssertEqual(session.groups.count, 1)
        XCTAssertEqual(session.exercises.count, 1)
    }

    func testQuickAddCooldownIsOffByDefaultButAppliesWhenEnabled() throws {
        var session = EditorV2Session(title: "Push")
        session.addExercise(named: "Bench Press")

        XCTAssertFalse(session.quickAddCooldown(from: .defaults))

        var prefs = WorkoutPreferences.defaults
        prefs.cooldown = CooldownPrefs(
            enabled: true,
            activities: [EnrichmentActivityPref(name: "Easy Bike", durationSec: 300)]
        )
        XCTAssertTrue(session.quickAddCooldown(from: prefs))
        let group = try XCTUnwrap(session.groups.values.first { $0.type == .cooldown })
        XCTAssertEqual(group.enrichmentKind, .cooldown)
        XCTAssertEqual(session.exercises.last?.name, "Easy Bike")
        XCTAssertEqual(session.exercises.last?.durationSeconds, 300)
    }

    func testEditingOneWarmupSetRowFlipsOnlyThatRow() throws {
        var session = EditorV2Session(title: "Push")
        let exercise = session.addExercise(named: "Bench Press")
        XCTAssertTrue(
            session.addDefaultWarmupSets(to: exercise.id, rows: WorkoutPreferences.defaults.defaultWarmupSetRows)
        )
        XCTAssertEqual(session.exercises[0].warmupSets.map(\.structureSource), [.enrichmentDefault, .enrichmentDefault])

        session.updateExercise(exercise.id) { $0.updateWarmupSetReps(at: 0, reps: 10) }
        let rows = session.exercises[0].warmupSets
        XCTAssertEqual(rows[0].reps, 10)
        XCTAssertEqual(rows[0].structureSource, .userAdded)
        XCTAssertEqual(rows[1].structureSource, .enrichmentDefault)
        // `sets` stays an Int — warm-up sets are a sibling list, never a reshape.
        XCTAssertEqual(session.exercises[0].sets, 3)
    }

    func testWarmupSetsSkipCardioShapesAndKeepSetsInt() {
        var session = EditorV2Session(title: "Conditioning")
        session.exercises = [EditorV2Exercise(name: "Row", durationSeconds: 600)]
        XCTAssertFalse(
            session.addDefaultWarmupSets(
                to: session.exercises[0].id,
                rows: WorkoutPreferences.defaults.defaultWarmupSetRows
            )
        )
        XCTAssertTrue(session.exercises[0].warmupSets.isEmpty)
        XCTAssertNil(session.exercises[0].sets)
    }

    func testEditingActivityNameFlipsRowToUserAdded() {
        var session = EditorV2Session(title: "Push")
        session.addExercise(named: "Bench Press")
        XCTAssertTrue(session.quickAddSessionWarmup(from: .defaults))
        let activityID = session.exercises[0].id

        session.updateExercise(activityID) { $0.renameActivity(to: "Jump Rope + Hips") }
        XCTAssertEqual(session.exercises[0].name, "Jump Rope + Hips")
        XCTAssertEqual(session.exercises[0].structureSource, .userAdded)
    }

    func testQuickAddRestStampsEnrichmentDefaultAndEditFlipsToUser() throws {
        var session = EditorV2Session(title: "Push")
        let exercise = session.addExercise(named: "Bench Press")

        XCTAssertTrue(try session.quickAddBetweenSetRest(to: exercise.id, restSec: 60, restOpen: false))
        XCTAssertEqual(session.exercises[0].restSeconds, 60)
        XCTAssertEqual(session.exercises[0].restOpen, false)
        XCTAssertEqual(
            session.exercises[0].fieldProvenance[WorkoutEnrichmentMutations.restSecKey],
            .enrichmentDefault
        )
        XCTAssertEqual(
            session.exercises[0].fieldProvenance[WorkoutEnrichmentMutations.restOpenKey],
            .enrichmentDefault
        )

        try session.exercises[0].setRestIntent(restSeconds: nil, restOpen: true)
        XCTAssertNil(session.exercises[0].restSeconds)
        XCTAssertEqual(session.exercises[0].fieldProvenance[WorkoutEnrichmentMutations.restSecKey], .user)
    }

    func testQuickAddRestRejectsContradictoryIntent() {
        var session = EditorV2Session(title: "Push")
        let exercise = session.addExercise(named: "Bench Press")
        XCTAssertThrowsError(
            try session.quickAddBetweenSetRest(to: exercise.id, restSec: 60, restOpen: true)
        ) { error in
            XCTAssertEqual(error as? WorkoutPreferencesValidationError, .restOpenWithRestSec)
        }
    }

    func testQuickAddRestDoesNotOverwriteUserOwnedRest() throws {
        var session = EditorV2Session(title: "Push")
        let exercise = session.addExercise(named: "Bench Press")
        try session.exercises[0].setRestIntent(restSeconds: 45, restOpen: false)

        XCTAssertFalse(try session.quickAddBetweenSetRest(to: exercise.id, restSec: 90, restOpen: false))
        XCTAssertEqual(session.exercises[0].restSeconds, 45)
        XCTAssertEqual(
            session.exercises[0].fieldProvenance[WorkoutEnrichmentMutations.restSecKey],
            .user
        )
    }

    func testParseListStripsExerciseIdOnKindScopedTombstones() {
        let parsed = EnrichmentTombstone.parseList([
            ["kind": "cooldown", "exercise_id": "wex_stray"],
            ["kind": "exercise_warmup_sets", "exercise_id": "wex_ok"],
            ["kind": "session_warmup"]
        ])
        XCTAssertEqual(
            parsed,
            [
                EnrichmentTombstone(kind: .cooldown),
                EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_ok"),
                EnrichmentTombstone(kind: .sessionWarmup)
            ]
        )
        XCTAssertTrue(WorkoutEnrichmentPresence.isTombstoned(.cooldown, tombstones: parsed))
    }

    func testRemoveSessionWarmupWritesKindTombstoneAndDropsWarmupType() {
        var session = EditorV2Session(title: "Push")
        session.addExercise(named: "Bench Press")
        XCTAssertTrue(session.quickAddSessionWarmup(from: .defaults))

        session.removeSessionWarmup()

        XCTAssertFalse(session.hasWarmupSection)
        XCTAssertEqual(session.exercises.map(\.name), ["Bench Press"])
        XCTAssertEqual(session.enrichmentTombstones, [EnrichmentTombstone(kind: .sessionWarmup)])
        XCTAssertNil(session.enrichmentTombstones.first?.exerciseId)
        // Tombstoned kinds are never re-added by quick add.
        XCTAssertFalse(session.quickAddSessionWarmup(from: .defaults))
        XCTAssertFalse(WorkoutEnrichmentPresence.hasWarmupBlock(in: session.toSocialImportBlocks()))
    }

    func testRemoveWarmupSetsWritesExerciseScopedTombstone() throws {
        var session = EditorV2Session(title: "Push")
        let exercise = session.addExercise(named: "Bench Press")
        XCTAssertTrue(
            session.addDefaultWarmupSets(to: exercise.id, rows: WorkoutPreferences.defaults.defaultWarmupSetRows)
        )

        let exerciseId = try XCTUnwrap(session.removeWarmupSets(from: exercise.id))

        XCTAssertTrue(session.exercises[0].warmupSets.isEmpty)
        XCTAssertEqual(
            session.enrichmentTombstones,
            [EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: exerciseId)]
        )
        XCTAssertTrue(exerciseId.hasPrefix("wex_"))
        // Tombstoned exercise never gets warm-up sets back.
        XCTAssertFalse(
            session.addDefaultWarmupSets(to: exercise.id, rows: WorkoutPreferences.defaults.defaultWarmupSetRows)
        )
    }

    func testRemoveBetweenSetRestClearsIntentAndProvenance() throws {
        var session = EditorV2Session(title: "Push")
        let exercise = session.addExercise(named: "Bench Press")
        XCTAssertTrue(try session.quickAddBetweenSetRest(to: exercise.id, restSec: 60, restOpen: false))

        session.removeBetweenSetRest(from: exercise.id)

        XCTAssertNil(session.exercises[0].restSeconds)
        XCTAssertNil(session.exercises[0].restOpen)
        XCTAssertNil(session.exercises[0].fieldProvenance[WorkoutEnrichmentMutations.restSecKey])
        XCTAssertEqual(session.enrichmentTombstones, [EnrichmentTombstone(kind: .betweenSetRest)])
    }

    func testClearTombstoneAllowsReapply() {
        var session = EditorV2Session(title: "Push")
        session.addExercise(named: "Bench Press")
        session.removeSessionWarmup()
        XCTAssertFalse(session.quickAddSessionWarmup(from: .defaults))

        session.clearEnrichmentTombstone(.sessionWarmup)

        XCTAssertTrue(session.quickAddSessionWarmup(from: .defaults))
    }

    // MARK: - Explicit re-opt-in (editor quick add clears the tombstone)

    func testExplicitQuickAddClearsSessionWarmupTombstone() throws {
        var session = EditorV2Session(title: "Push")
        session.addExercise(named: "Bench Press")
        XCTAssertTrue(session.quickAddSessionWarmup(from: .defaults))
        session.removeSessionWarmup()
        XCTAssertEqual(session.enrichmentTombstones, [EnrichmentTombstone(kind: .sessionWarmup)])

        XCTAssertTrue(session.quickAddSessionWarmup(from: .defaults, clearingTombstone: true))

        XCTAssertTrue(session.hasWarmupSection)
        XCTAssertTrue(session.enrichmentTombstones.isEmpty)
    }

    func testExplicitQuickAddClearsCooldownTombstone() throws {
        var prefs = WorkoutPreferences.defaults
        prefs.cooldown = CooldownPrefs(
            enabled: true,
            activities: [EnrichmentActivityPref(name: "Easy Bike", durationSec: 300)]
        )
        var session = EditorV2Session(title: "Push")
        session.addExercise(named: "Bench Press")
        XCTAssertTrue(session.quickAddCooldown(from: prefs))
        session.removeCooldown()
        XCTAssertFalse(session.quickAddCooldown(from: prefs))

        XCTAssertTrue(session.quickAddCooldown(from: prefs, clearingTombstone: true))

        XCTAssertTrue(session.hasCooldownSection)
        XCTAssertTrue(session.enrichmentTombstones.isEmpty)
    }

    func testExplicitQuickAddClearsWarmupSetsTombstoneForThatExerciseOnly() throws {
        var session = EditorV2Session(title: "Push")
        let bench = session.addExercise(named: "Bench Press")
        let row = session.addExercise(named: "Barbell Row")
        let rows = WorkoutPreferences.defaults.defaultWarmupSetRows
        XCTAssertTrue(session.addDefaultWarmupSets(to: bench.id, rows: rows))
        XCTAssertTrue(session.addDefaultWarmupSets(to: row.id, rows: rows))
        let benchExerciseId = try XCTUnwrap(session.removeWarmupSets(from: bench.id))
        let rowExerciseId = try XCTUnwrap(session.removeWarmupSets(from: row.id))

        XCTAssertTrue(session.addDefaultWarmupSets(to: bench.id, rows: rows, clearingTombstone: true))

        XCTAssertEqual(session.exercises[0].warmupSets.map(\.reps), [8, 5])
        XCTAssertEqual(
            session.enrichmentTombstones,
            [EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: rowExerciseId)]
        )
        XCTAssertFalse(
            WorkoutEnrichmentPresence.isTombstoned(
                .exerciseWarmupSets,
                exerciseId: benchExerciseId,
                tombstones: session.enrichmentTombstones
            )
        )
    }

    func testExplicitQuickAddClearsBetweenSetRestTombstone() throws {
        var session = EditorV2Session(title: "Push")
        let exercise = session.addExercise(named: "Bench Press")
        session.removeBetweenSetRest(from: exercise.id)
        XCTAssertFalse(try session.quickAddBetweenSetRest(to: exercise.id, restSec: 90, restOpen: false))

        XCTAssertTrue(
            try session.quickAddBetweenSetRest(
                to: exercise.id,
                restSec: 90,
                restOpen: false,
                clearingTombstone: true
            )
        )

        XCTAssertEqual(session.exercises[0].restSeconds, 90)
        XCTAssertTrue(session.enrichmentTombstones.isEmpty)
    }

    func testExplicitQuickAddStillBlockedByPresenceByType() {
        var session = EditorV2Session(title: "Push")
        let key = "existing-warmup"
        session.groups[key] = EditorV2Group(
            id: key,
            type: .warmup,
            name: "Warm-up",
            structureSource: .explicit
        )
        session.exercises = [EditorV2Exercise(name: "Row 500m", durationSeconds: 300, groupKey: key)]

        XCTAssertFalse(session.quickAddSessionWarmup(from: .defaults, clearingTombstone: true))
        XCTAssertEqual(session.groups.count, 1)
    }

    // MARK: - Save payload round-trip

    func testSavePayloadCarriesDeclaredEnrichmentFields() throws {
        var session = EditorV2Session(title: "Push")
        let exercise = session.addExercise(named: "Bench Press")
        XCTAssertTrue(session.quickAddSessionWarmup(from: .defaults))
        XCTAssertTrue(
            session.addDefaultWarmupSets(to: exercise.id, rows: WorkoutPreferences.defaults.defaultWarmupSetRows)
        )
        XCTAssertTrue(try session.quickAddBetweenSetRest(to: exercise.id, restSec: 60, restOpen: false))
        session.mintMissingExerciseIDs()

        let blocks = session.toSocialImportBlocks()
        let warmupBlock = try XCTUnwrap(blocks.first { $0.type == StructureBlockType.warmup.rawValue })
        XCTAssertEqual(warmupBlock.enrichmentKind, EnrichmentKind.sessionWarmup.rawValue)
        XCTAssertEqual(warmupBlock.structureSource, StructureSource.enrichmentDefault.rawValue)
        XCTAssertEqual(
            warmupBlock.exercises.first?.structureSource,
            StructureSource.enrichmentDefault.rawValue
        )

        let request = WorkoutSaveRequest(
            name: "Push",
            sport: "strength",
            intervals: session.toSaveIntervals(),
            blocks: blocks,
            enrichmentTombstones: [EnrichmentTombstone(kind: .cooldown)]
        )
        let body = try APIService.mapperSaveBody(from: request, source: "manual")
        let workoutData = try XCTUnwrap(body["workout_data"] as? [String: Any])
        XCTAssertNil(
            workoutData["enrichment_tombstones"],
            "Top-level tombstones are forbidden by WorkoutData — use metadata"
        )
        let metadata = try XCTUnwrap(workoutData["metadata"] as? [String: Any])
        let tombstones = try XCTUnwrap(metadata["enrichment_tombstones"] as? [[String: Any]])
        XCTAssertEqual(tombstones.first?["kind"] as? String, "cooldown")

        let clearRequest = WorkoutSaveRequest(
            name: "Push",
            sport: "strength",
            intervals: session.toSaveIntervals(),
            blocks: blocks,
            enrichmentTombstones: []
        )
        let clearBody = try APIService.mapperSaveBody(from: clearRequest, source: "manual")
        let clearData = try XCTUnwrap(clearBody["workout_data"] as? [String: Any])
        let clearMeta = try XCTUnwrap(clearData["metadata"] as? [String: Any])
        let cleared = try XCTUnwrap(clearMeta["enrichment_tombstones"] as? [[String: Any]])
        XCTAssertTrue(cleared.isEmpty)

        let openRestExercise = SocialImportExercise(
            name: "Bench Press",
            sets: 4,
            reps: 8,
            restSeconds: 60,
            restOpen: true
        )
        let openRestPayload = APIService.provenanceExercise(from: openRestExercise)
        XCTAssertEqual(openRestPayload["rest_open"] as? Bool, true)
        XCTAssertNil(openRestPayload["rest_sec"])

        let encodedBlocks = try XCTUnwrap(workoutData["blocks"] as? [[String: Any]])
        let encodedWarmup = try XCTUnwrap(
            encodedBlocks.first { $0["type"] as? String == StructureBlockType.warmup.rawValue }
        )
        XCTAssertEqual(encodedWarmup["enrichment_kind"] as? String, "session_warmup")

        let workExercise = try XCTUnwrap(
            encodedBlocks
                .compactMap { $0["exercises"] as? [[String: Any]] }
                .flatMap { $0 }
                .first { $0["name"] as? String == "Bench Press" }
        )
        XCTAssertEqual(workExercise["sets"] as? Int, 3)
        XCTAssertEqual(workExercise["rest_sec"] as? Int, 60)
        XCTAssertEqual(workExercise["rest_open"] as? Bool, false)
        let exerciseId = try XCTUnwrap(workExercise["exercise_id"] as? String)
        XCTAssertTrue(exerciseId.hasPrefix("wex_"))
        let warmupSets = try XCTUnwrap(workExercise["warmup_sets"] as? [[String: Any]])
        XCTAssertEqual(warmupSets.map { $0["reps"] as? Int }, [8, 5])
        XCTAssertEqual(warmupSets.first?["structure_source"] as? String, "enrichment_default")
        let provenance = try XCTUnwrap(workExercise["field_provenance"] as? [String: String])
        XCTAssertEqual(provenance["rest_sec"], "enrichment_default")
    }

    func testIngestParsesDeclaredEnrichmentFields() throws {
        let json = """
        {
          "title": "Push",
          "enrichment_tombstones": [
            {"kind": "cooldown"},
            {"kind": "exercise_warmup_sets", "exercise_id": "wex_abc"},
            {"kind": "not_a_kind"}
          ],
          "blocks": [
            {
              "type": "warmup",
              "label": "Warm-up",
              "enrichment_kind": "session_warmup",
              "structure_source": "enrichment_default",
              "rest_open": true,
              "field_provenance": {"rest_open": "enrichment_default"},
              "exercises": [
                {"name": "Jump Rope", "structure_source": "enrichment_default"}
              ]
            },
            {
              "type": "sets",
              "label": "Main",
              "exercises": [
                {
                  "name": "Bench Press",
                  "exercise_id": "wex_abc",
                  "sets": 4,
                  "reps": 8,
                  "rest_sec": 60,
                  "rest_open": false,
                  "field_provenance": {"rest_sec": "enrichment_default"},
                  "warmup_sets": [
                    {"reps": 8, "structure_source": "enrichment_default"},
                    {"reps": 5, "structure_source": "user_added"}
                  ]
                }
              ]
            }
          ]
        }
        """
        let draft = try SocialImportDraft.fromIngestJSON(
            Data(json.utf8),
            platform: .manual,
            sourceURL: nil,
            equipmentEmpty: false,
            equipmentNote: nil
        )

        XCTAssertEqual(
            draft.enrichmentTombstones,
            [
                EnrichmentTombstone(kind: .cooldown),
                EnrichmentTombstone(kind: .exerciseWarmupSets, exerciseId: "wex_abc")
            ]
        )
        XCTAssertTrue(WorkoutEnrichmentPresence.hasWarmupBlock(in: draft.blocks))

        let warmupBlock = try XCTUnwrap(draft.blocks.first { $0.type == "warmup" })
        XCTAssertEqual(warmupBlock.enrichmentKind, "session_warmup")
        XCTAssertEqual(warmupBlock.restOpen, true)
        XCTAssertEqual(warmupBlock.fieldProvenance?["rest_open"], "enrichment_default")

        let bench = try XCTUnwrap(draft.exercises.first { $0.name == "Bench Press" })
        XCTAssertEqual(bench.exerciseId, "wex_abc")
        XCTAssertEqual(bench.sets, 4)
        XCTAssertEqual(bench.restOpen, false)
        XCTAssertEqual(bench.fieldProvenance?["rest_sec"], "enrichment_default")
        XCTAssertEqual(
            bench.warmupSets?.map(\.structureSource),
            [.enrichmentDefault, .userAdded]
        )
        XCTAssertEqual(bench.warmupSets?.map(\.reps), [8, 5])
    }

    func testPersistenceKeepsEnrichmentFieldsOnReconcile() throws {
        var draft = try SocialImportDraft.fromIngestJSON(
            Data(#"{"title":"Push","blocks":[{"type":"sets","label":"Main","enrichment_kind":null,"exercises":[{"name":"Bench Press","sets":4,"reps":8,"exercise_id":"wex_abc","rest_open":false,"warmup_sets":[{"reps":8}]}]}]}"#.utf8),
            platform: .manual,
            sourceURL: nil,
            equipmentEmpty: false,
            equipmentNote: nil
        )
        draft.blocks[0].enrichmentKind = EnrichmentKind.cooldown.rawValue
        draft.blocks[0].restOpen = true
        draft.blocks[0].fieldProvenance = ["rest_open": ProvSource.enrichmentDefault.rawValue]

        let persisted = draft.blocksForPersistence()
        XCTAssertEqual(persisted.first?.enrichmentKind, EnrichmentKind.cooldown.rawValue)
        XCTAssertEqual(persisted.first?.restOpen, true)
        XCTAssertEqual(persisted.first?.fieldProvenance?["rest_open"], "enrichment_default")
        XCTAssertEqual(persisted.first?.exercises.first?.exerciseId, "wex_abc")
        XCTAssertEqual(persisted.first?.exercises.first?.warmupSets?.count, 1)
    }

    // MARK: - Enrich API shapes

    func testEnrichRequestBodyUsesDeclaredKeys() throws {
        let request = EnrichRequest(
            blocksJSON: ["blocks": [["type": "sets", "exercises": [["name": "Bench Press", "sets": 4]]]]],
            prefs: .defaults,
            tombstones: [EnrichmentTombstone(kind: .cooldown)],
            mode: .editor
        )
        let object = try request.jsonObject()
        XCTAssertEqual(object["mode"] as? String, "editor")
        XCTAssertNotNil(object["blocks_json"])
        XCTAssertNotNil(object["prefs"])
        let tombstones = try XCTUnwrap(object["tombstones"] as? [[String: Any]])
        XCTAssertEqual(tombstones.first?["kind"] as? String, "cooldown")
        XCTAssertNoThrow(try request.jsonData())
    }

    func testEnrichResponseDecodesSummaryBuckets() throws {
        let json = """
        {
          "blocks_json": {"blocks": []},
          "enrichment_applied": {
            "prefs_source": "user_stored",
            "added": ["exercise_warmup_sets"],
            "refreshed": ["between_set_rest"],
            "skipped_tombstoned": ["cooldown"],
            "skipped_already_present": ["session_warmup"],
            "skipped_no_identity": ["Bench Press"],
            "skipped_tombstoned_exercises": ["wex_abc"]
          }
        }
        """
        let response = try EnrichResponse.from(data: Data(json.utf8))
        let summary = try XCTUnwrap(response.enrichmentApplied)
        XCTAssertEqual(summary.prefsSource, "user_stored")
        XCTAssertEqual(summary.added, ["exercise_warmup_sets"])
        XCTAssertEqual(summary.refreshed, ["between_set_rest"])
        XCTAssertEqual(summary.skippedTombstoned, ["cooldown"])
        XCTAssertEqual(summary.skippedAlreadyPresent, ["session_warmup"])
        XCTAssertEqual(summary.skippedNoIdentity, ["Bench Press"])
        XCTAssertEqual(summary.skippedTombstonedExercises, ["wex_abc"])
    }

    func testEnrichResponseWithoutSummaryDecodes() throws {
        let response = try EnrichResponse.from(data: Data(#"{"blocks_json":{"blocks":[]}}"#.utf8))
        XCTAssertNil(response.enrichmentApplied)
    }
}

// MARK: - Decode probes

private struct SourceProbe: Decodable {
    var structureSource: StructureSource

    enum CodingKeys: String, CodingKey {
        case structureSource = "structure_source"
    }
}

private struct ProvProbe: Decodable {
    var prov: ProvSource
}
