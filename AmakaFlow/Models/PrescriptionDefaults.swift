import Foundation

/// Client-side soft defaults when backend sanitize omitted sets/rest/reps (AMA-2311 Task 8).
/// Mirrors `prescription_sanitize.apply_prescription_defaults` guards — never overwrites source values.
enum PrescriptionDefaults {
    static let clientFallbackFlagKey = "prescription_defaults_client_fallback"

    static let defaultSets = 3
    static let defaultRestSec = 60
    static let defaultReps = 10

    private static let formatGroups: Set<String> = [
        "superset", "circuit", "emom", "tabata", "amrap", "for-time", "fortime", "rounds"
    ]

    static func blockOwnsRoundsOrRest(structure: String?, type: String?) -> Bool {
        if let normalized = normalizedToken(structure), formatGroups.contains(normalized) {
            return true
        }
        if let normalized = normalizedToken(type), formatGroups.contains(normalized) {
            return true
        }
        return false
    }

    /// Apply soft defaults to one exercise. Returns true when any field was inferred.
    @discardableResult
    static func applyIfNeeded(
        to exercise: inout SocialImportExercise,
        roundsOwnedByFormat: Bool,
        recordAnalytics: Bool = true
    ) -> Bool {
        var applied = false

        if exercise.sets == nil, !roundsOwnedByFormat {
            exercise.sets = defaultSets
            applied = true
        }

        if !roundsOwnedByFormat, exercise.restSeconds == nil {
            exercise.restSeconds = defaultRestSec
            applied = true
        }

        if shouldDefaultReps(exercise) {
            exercise.reps = defaultReps
            applied = true
        }

        if applied, recordAnalytics {
            markClientFallbackUsed()
        }
        return applied
    }

    /// Walk draft blocks and apply defaults where backend left gaps.
    static func applyToDraft(_ draft: inout SocialImportDraft) {
        var anyApplied = false
        for blockIndex in draft.blocks.indices {
            let block = draft.blocks[blockIndex]
            let owned = blockOwnsRoundsOrRest(structure: block.type, type: block.type)
            for exerciseIndex in draft.blocks[blockIndex].exercises.indices {
                let applied = applyIfNeeded(
                    to: &draft.blocks[blockIndex].exercises[exerciseIndex],
                    roundsOwnedByFormat: owned,
                    recordAnalytics: false
                )
                if applied { anyApplied = true }
            }
        }
        draft.exercises = draft.blocks.flatMap(\.exercises)
        if anyApplied {
            markClientFallbackUsed()
        }
    }

    static func markClientFallbackUsed() {
        UserDefaults.standard.set(true, forKey: clientFallbackFlagKey)
        Task { @MainActor in
            DebugLogService.shared.log(
                "Prescription client fallback",
                details: "Applied soft defaults after ingest omitted sets/rest/reps",
                metadata: [clientFallbackFlagKey: "true"]
            )
        }
    }

    static var clientFallbackWasUsed: Bool {
        UserDefaults.standard.bool(forKey: clientFallbackFlagKey)
    }

    #if DEBUG
    static func resetClientFallbackFlagForTesting() {
        UserDefaults.standard.removeObject(forKey: clientFallbackFlagKey)
    }
    #endif

    private static func shouldDefaultReps(_ exercise: SocialImportExercise) -> Bool {
        if exercise.reps != nil { return false }
        if let range = exercise.repsRange?.trimmingCharacters(in: .whitespacesAndNewlines), !range.isEmpty {
            return false
        }
        if let seconds = exercise.seconds, seconds > 0 { return false }
        if let meters = exercise.distanceMeters, meters > 0 { return false }
        if hasLoadOrWeight(exercise.load) { return false }
        return true
    }

    private static func hasLoadOrWeight(_ load: String?) -> Bool {
        guard let load else { return false }
        let trimmed = load.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    private static func normalizedToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.isEmpty ? nil : text
    }
}

extension PrescriptionFormatter {
    static func effective(from exercise: SocialImportExercise) -> EffectivePrescription {
        let repsRange = exercise.repsRange.flatMap { RepsRange.parse($0) }
        var secondary = secondaryParts(
            load: exercise.load.flatMap { text in
                let resolved = Workout.resolveLegacyLoadAndInstruction(from: text)
                return resolved.load
            },
            notes: exercise.notes,
            restSeconds: exercise.restSeconds,
            rangeQualifier: repsRange?.qualifier
        )

        let primary = resolvePrimaryMetric(
            PrescriptionMetricInputs(
                durationSeconds: exercise.seconds,
                distanceMeters: exercise.distanceMeters,
                calories: nil,
                plainReps: exercise.reps,
                repsRange: repsRange,
                sets: exercise.sets
            )
        )

        if case .repsRange(let range, _) = primary, let qualifier = range.qualifier {
            if !secondary.contains(qualifier) {
                secondary.append(qualifier)
            }
        }

        return EffectivePrescription(primary: primary, secondary: secondary)
    }

    /// Map editor row → save/push interval using the same primary metric as UI.
    static func saveInterval(from exercise: EditorV2Exercise) -> WorkoutSaveInterval {
        let load = exercise.weightKg.map(EditorV2Exercise.formatWeightLoad)
        return saveInterval(
            name: exercise.name,
            prescription: effective(from: exercise),
            restSeconds: exercise.restSeconds,
            load: load
        )
    }

    /// Map social-import row → save interval (preview save path).
    static func saveInterval(from exercise: SocialImportExercise) -> WorkoutSaveInterval {
        let instruction = exercise.detailInstruction
        return saveInterval(
            name: exercise.name,
            prescription: effective(from: exercise),
            restSeconds: exercise.restSeconds,
            load: instruction
        )
    }

    private static func saveInterval(
        name: String,
        prescription: EffectivePrescription,
        restSeconds: Int?,
        load: String?
    ) -> WorkoutSaveInterval {
        switch prescription.primary {
        case .duration(let seconds, _):
            return WorkoutSaveInterval(
                type: "time",
                name: name,
                seconds: seconds,
                restSeconds: restSeconds,
                load: load
            )
        case .distance(let meters, _):
            return WorkoutSaveInterval(
                type: "distance",
                name: name,
                meters: meters,
                restSeconds: restSeconds,
                load: load
            )
        case .calories(let calories, _):
            return WorkoutSaveInterval(
                type: "time",
                name: name,
                seconds: calories,
                restSeconds: restSeconds,
                load: load,
                target: "\(calories) cal"
            )
        case .reps(let reps, let sets):
            return WorkoutSaveInterval(
                type: "reps",
                name: name,
                sets: sets ?? PrescriptionDefaults.defaultSets,
                reps: reps,
                restSeconds: restSeconds ?? PrescriptionDefaults.defaultRestSec,
                load: load
            )
        case .repsRange(let range, let sets):
            return WorkoutSaveInterval(
                type: "reps",
                name: name,
                sets: sets ?? PrescriptionDefaults.defaultSets,
                reps: (range.low + range.high) / 2,
                restSeconds: restSeconds ?? PrescriptionDefaults.defaultRestSec,
                load: load,
                target: range.display
            )
        case .none(let sets):
            return WorkoutSaveInterval(
                type: "reps",
                name: name,
                sets: sets ?? PrescriptionDefaults.defaultSets,
                reps: PrescriptionDefaults.defaultReps,
                restSeconds: restSeconds ?? PrescriptionDefaults.defaultRestSec,
                load: load
            )
        }
    }
}
