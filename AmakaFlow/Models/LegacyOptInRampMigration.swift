//
//  LegacyOptInRampMigration.swift
//  AmakaFlow
//
//  AMA-2408 F2 — one-time conversion of the v1 global-default warm-up path
//  into explicit `perExercise` entries so already-configured workouts keep
//  the same applied ramps after opt-in lands.
//

import Foundation

enum LegacyOptInRampMigration {
    static let flagKeyPrefix = "ama2408_legacy_optin_ramp_migrated_"

    /// Legacy shape: warm-ups enabled with nil/empty `perExercise` (v1 path
    /// that auto-applied `default_sets` to every non-excluded candidate).
    static func needsMigration(_ prefs: ExerciseWarmupSetsPrefs) -> Bool {
        guard prefs.enabled else { return false }
        let ramps = prefs.perExercise ?? []
        return ramps.isEmpty
    }

    /// Materialize global `default_sets` into explicit enabled ramps for every
    /// candidate not already excluded. Idempotent when `perExercise` is already
    /// populated.
    static func materialize(
        prefs: ExerciseWarmupSetsPrefs,
        candidateNames: [String]
    ) -> ExerciseWarmupSetsPrefs {
        var next = prefs
        let existing = next.perExercise ?? []
        guard existing.isEmpty else { return next }

        let excluded = Set(prefs.excludeExerciseKeys.map(ExerciseKeyNormalizer.normalize))
        let defaultSets = prefs.defaultSets.isEmpty
            ? ExerciseWarmupSetsPrefs.defaults.defaultSets
            : prefs.defaultSets
        let rampSets = rampSets(from: defaultSets)

        next.perExercise = candidateNames.compactMap { name in
            let key = ExerciseKeyNormalizer.normalize(name)
            guard !excluded.contains(key) else { return nil }
            return PerExerciseRamp(exerciseRef: name, enabled: true, sets: rampSets)
        }
        return next
    }

    /// Convert a persisted decision that still looks like the global path.
    static func materializePersisted(
        _ persisted: EnrichmentState.Persisted,
        candidateNames: [String],
        defaultSets: [WarmupSetDefault] = ExerciseWarmupSetsPrefs.defaults.defaultSets
    ) -> EnrichmentState.Persisted {
        guard persisted.checkedKindSet.contains(.exerciseWarmupSets),
              persisted.perExerciseRamps.isEmpty,
              !candidateNames.isEmpty
        else { return persisted }

        var next = persisted
        let rampSets = rampSets(from: defaultSets)
        next.perExerciseRamps = candidateNames.map { name in
            PerExerciseRamp(exerciseRef: name, enabled: true, sets: rampSets)
        }
        return next
    }

    /// One-shot per workout id. Returns migrated prefs when conversion ran.
    @discardableResult
    static func migrateIfNeeded(
        workoutID: String,
        prefs: ExerciseWarmupSetsPrefs,
        candidateNames: [String],
        defaults: UserDefaults = .standard
    ) -> ExerciseWarmupSetsPrefs {
        guard !workoutID.isEmpty else { return prefs }
        let flag = flagKeyPrefix + workoutID
        guard !defaults.bool(forKey: flag) else { return prefs }
        // No candidates yet → plan has not loaded. Retry next call; do not
        // consume the one-shot flag.
        guard !candidateNames.isEmpty else { return prefs }
        guard needsMigration(prefs) else {
            defaults.set(true, forKey: flag)
            return prefs
        }
        let migrated = materialize(prefs: prefs, candidateNames: candidateNames)
        defaults.set(true, forKey: flag)
        return migrated
    }

    /// Explicit one-shot marker write for callers that already persisted migrated
    /// prefs and only need to consume the retry flag (no synthetic prefs).
    static func markMigrated(workoutID: String, defaults: UserDefaults = .standard) {
        guard !workoutID.isEmpty else { return }
        defaults.set(true, forKey: flagKeyPrefix + workoutID)
    }

    /// Effective ramp map under the OLD v1 interpretation (global default_sets
    /// on every non-excluded candidate). Used by the byte-identical migration test.
    static func legacyEffectiveRamps(
        prefs: ExerciseWarmupSetsPrefs,
        candidateNames: [String]
    ) -> [String: [RampSet]] {
        let excluded = Set(prefs.excludeExerciseKeys.map(ExerciseKeyNormalizer.normalize))
        let sets = rampSets(from: prefs.defaultSets.isEmpty
            ? ExerciseWarmupSetsPrefs.defaults.defaultSets
            : prefs.defaultSets)
        var map: [String: [RampSet]] = [:]
        for name in candidateNames {
            let key = ExerciseKeyNormalizer.normalize(name)
            guard !excluded.contains(key) else { continue }
            map[key] = sets
        }
        return map
    }

    /// Effective ramp map under the NEW opt-in interpretation.
    static func optInEffectiveRamps(
        prefs: ExerciseWarmupSetsPrefs,
        candidateNames: [String]
    ) -> [String: [RampSet]] {
        let excluded = Set(prefs.excludeExerciseKeys.map(ExerciseKeyNormalizer.normalize))
        var map: [String: [RampSet]] = [:]
        for ramp in prefs.perExercise ?? [] {
            guard ramp.enabled, !ramp.sets.isEmpty else { continue }
            let key = ExerciseKeyNormalizer.normalize(ramp.exerciseRef)
            guard !excluded.contains(key) else { continue }
            if candidateNames.isEmpty
                || candidateNames.contains(where: { ExerciseKeyNormalizer.normalize($0) == key }) {
                map[key] = ramp.sets
            }
        }
        return map
    }

    private static func rampSets(from defaults: [WarmupSetDefault]) -> [RampSet] {
        if defaults.isEmpty {
            return WorkoutEnrichmentMutations.defaultRampSets()
        }
        let converted = defaults.compactMap { row in
            try? RampSet(kind: .reps, value: row.reps)
        }
        return converted.isEmpty ? WorkoutEnrichmentMutations.defaultRampSets() : converted
    }
}
