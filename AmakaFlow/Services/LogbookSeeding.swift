//
//  LogbookSeeding.swift
//  AmakaFlow
//
//  AMA-2426: seed logbook entries from a library workout plan or blank.
//

import Foundation

enum LogbookSeeding { // swiftlint:disable:this type_body_length
    /// Prefill from a Library workout's blocks (rounds-as-sets when `sets` is nil).
    static func draft(
        from workout: Workout,
        mode: LogbookMode,
        attachedSessionId: String? = nil,
        ghostLookup: ActualsGhostLookingUp? = nil,
        loadPlanLookup: ((String) -> [SetActual]?)? = nil,
        now: Date = Date()
    ) -> LogDraft {
        let entries = entries(from: workout, ghostLookup: ghostLookup, loadPlanLookup: loadPlanLookup)
        return LogDraft(
            workoutId: workout.id,
            title: workout.name,
            subtitle: subtitle(for: now),
            startedAt: now,
            lastEditedAt: now,
            state: LogbookModeInference.draftState(for: mode),
            mode: mode,
            attachedSessionId: attachedSessionId,
            entries: entries
        )
    }

    static func draft(
        from session: ActualsFillInSession,
        mode: LogbookMode = .after,
        ghostLookup: ActualsGhostLookingUp? = nil,
        now: Date = Date()
    ) -> LogDraft {
        LogDraft(
            id: session.id,
            title: session.title,
            subtitle: session.subtitle,
            startedAt: now,
            lastEditedAt: now,
            state: LogbookModeInference.draftState(for: mode),
            mode: mode,
            attachedSessionId: session.id,
            entries: LogbookRollup.entries(from: session, ghostLookup: ghostLookup),
            rpe: session.rpe
        )
    }

    /// Blank notepad — one empty exercise row.
    static func blankDraft(mode: LogbookMode, now: Date = Date()) -> LogDraft {
        let planned = ExerciseActualPlanned(sets: 3, reps: 8, weightKg: nil)
        let sets = (1...3).map { SetActual(index: $0) }
        let ghosts = LogbookGhosts.ghosts(
            setCount: 3,
            planned: planned,
            lastSetActuals: nil,
            lastExerciseActual: nil
        )
        let entry = LogbookExerciseEntry(
            id: "exercise_1",
            name: "Exercise 1",
            planned: planned,
            sets: sets,
            ghosts: ghosts
        )
        return LogDraft(
            title: "Logged session",
            subtitle: subtitle(for: now),
            startedAt: now,
            lastEditedAt: now,
            state: LogbookModeInference.draftState(for: mode),
            mode: mode,
            entries: [entry]
        )
    }

    static func entries(
        from workout: Workout,
        ghostLookup: ActualsGhostLookingUp? = nil,
        loadPlanLookup: ((String) -> [SetActual]?)? = nil
    ) -> [LogbookExerciseEntry] {
        // Prefer blocks — detail's "N ROUNDS" lives on `block.rounds` when `exercise.sets` is nil.
        // Flattening via intervals drops that for straight blocks (no `.repeat` wrapper).
        let planned = plannedItems(from: workout.blocks)
        guard !planned.isEmpty else {
            return blankDraft(mode: .after).entries
        }

        return planned.map { item in
            // Ghosts / load plans key by exercise name; entry id must be unique per station
            // so two "Warm-up · OHP" rows don't share focus / Next set › state.
            let ghostKey = item.ghostKey
            let lastActual = try? ghostLookup?.latestActual(exerciseKey: ghostKey)
            let loadPlan = loadPlanLookup?(ghostKey)

            if item.loggingKind == .metric {
                return metricEntry(item: item, loadPlan: loadPlan)
            }

            let setCount = max(item.sets, loadPlan?.count ?? 0, 1)
            let sets: [SetActual] = (1...setCount).map { index in
                if let target = loadPlan?.first(where: { $0.index == index }) {
                    return SetActual(
                        index: index,
                        isWarmup: target.isWarmup,
                        weightKg: target.weightKg,
                        reps: target.reps,
                        durationSeconds: target.durationSeconds,
                        calories: target.calories,
                        distanceMeters: target.distanceMeters,
                        checkedAt: nil
                    )
                }
                return SetActual(index: index, isWarmup: false)
            }

            let plannedModel = ExerciseActualPlanned(
                sets: item.sets,
                reps: item.reps,
                weightKg: item.weightKg
            )
            let ghosts = LogbookGhosts.ghosts(
                setCount: sets.count,
                planned: plannedModel,
                lastSetActuals: nil,
                lastExerciseActual: lastActual
            )

            return LogbookExerciseEntry(
                id: item.entryID,
                name: item.name,
                planned: plannedModel,
                sets: sets,
                ghosts: ghosts,
                structureHeader: item.structureHeader,
                structureBlockIndex: item.structureBlockIndex,
                supersetPartner: item.supersetPartner,
                loggingKind: .strength
            )
        }
    }

    // MARK: - Private

    private struct PlannedItem {
        /// Unique per station in this workout (never reuse across duplicate names).
        var entryID: String
        /// Name-based key for ghosts / load plans.
        var ghostKey: String
        var name: String
        var sets: Int
        var reps: Int
        var weightKg: Double?
        var loggingKind: LogbookLoggingKind
        var durationSeconds: Int?
        var calories: Int?
        var distanceMeters: Int?
        var structureHeader: String?
        var structureBlockIndex: Int?
        var supersetPartner: String?
    }

    private static func metricEntry(
        item: PlannedItem,
        loadPlan: [SetActual]?
    ) -> LogbookExerciseEntry {
        let target = loadPlan?.first
        let bout = SetActual(
            index: 1,
            weightKg: nil,
            reps: nil,
            durationSeconds: target?.durationSeconds,
            calories: target?.calories,
            distanceMeters: target?.distanceMeters ?? item.distanceMeters.map(Double.init)
        )
        let ghost = LogbookGhosts.metricGhost(
            plannedDurationSeconds: item.durationSeconds,
            plannedCalories: item.calories,
            plannedDistanceMeters: item.distanceMeters
        )
        let note: String? = {
            if let duration = item.durationSeconds {
                return LogbookMetricFormat.duration(duration)
            }
            if let calories = item.calories {
                return "\(calories) CAL"
            }
            if let meters = item.distanceMeters {
                return LogbookMetricFormat.distance(
                    meters: Double(meters),
                    scale: .forExercise(named: item.name),
                    unit: .stored
                )
            }
            return "TIME / CAL"
        }()
        let plannedModel = ExerciseActualPlanned(sets: 1, reps: 1, weightKg: nil, note: note)
        return LogbookExerciseEntry(
            id: item.entryID,
            name: item.name,
            planned: plannedModel,
            sets: [bout],
            ghosts: [ghost],
            structureHeader: item.structureHeader,
            structureBlockIndex: item.structureBlockIndex,
            supersetPartner: item.supersetPartner,
            loggingKind: .metric,
            plannedDurationSeconds: item.durationSeconds,
            plannedCalories: item.calories,
            plannedDistanceMeters: item.distanceMeters,
            cardioStrip: LogbookCardioStrip(
                timeText: item.durationSeconds.map(LogbookMetricFormat.duration),
                distanceText: item.distanceMeters.map {
                    LogbookMetricFormat.distance(
                        meters: Double($0),
                        scale: .forExercise(named: item.name),
                        unit: .stored
                    )
                },
                caloriesText: item.calories.map { "\($0)" },
                heartRateText: nil,
                sourceNote: nil
            )
        )
    }

    /// Library blocks → logbook rows. Matches detail rounds-as-sets
    /// (`WorkoutDurationEstimator.effectiveSets` / DD detail line).
    private static func plannedItems(from blocks: [Block]) -> [PlannedItem] {
        var result: [PlannedItem] = []
        var usedEntryIDs = Set<String>()
        var ghostOccurrence: [String: Int] = [:]
        for (blockIndex, block) in blocks.enumerated() {
            if isWarmupOrCooldown(block) { continue }
            let multi = WorkoutDurationEstimator.isMultiStation(block)
            var stations: [PlannedItem] = []
            for (stationIndex, exercise) in block.exercises.enumerated() {
                guard var item = stationItem(
                    exercise: exercise,
                    block: block,
                    multiStation: multi,
                    blockIndex: blockIndex,
                    stationIndex: stationIndex,
                    usedEntryIDs: &usedEntryIDs,
                    ghostOccurrence: &ghostOccurrence
                ) else { continue }
                stations.append(item)
            }
            guard !stations.isEmpty else { continue }
            if stations.count == 2 {
                stations[0].supersetPartner = stations[1].name
                stations[1].supersetPartner = stations[0].name
            }
            result.append(contentsOf: stations)
        }
        return result
    }

    // swiftlint:disable:next function_parameter_count
    private static func stationItem(
        exercise: Exercise,
        block: Block,
        multiStation: Bool,
        blockIndex: Int,
        stationIndex: Int,
        usedEntryIDs: inout Set<String>,
        ghostOccurrence: inout [String: Int]
    ) -> PlannedItem? {
        let header = structureHeader(for: block, multiStation: multiStation)
        let ghostKey = ActualsGhostFeed.exerciseKey(forName: exercise.name)
        let occurrence = ghostOccurrence[ghostKey, default: 0]
        ghostOccurrence[ghostKey] = occurrence + 1
        let entryID = uniqueEntryID(
            preferred: exercise.id,
            ghostKey: ghostKey,
            blockIndex: blockIndex,
            stationIndex: stationIndex,
            occurrence: occurrence,
            used: &usedEntryIDs
        )

        if isMetricStation(exercise) {
            let duration = exercise.durationSeconds
            let distance = exercise.distance.map { Int($0.rounded()) }
            return PlannedItem(
                entryID: entryID,
                ghostKey: ghostKey,
                name: exercise.name,
                sets: 1,
                reps: 1,
                weightKg: nil,
                loggingKind: .metric,
                durationSeconds: duration,
                calories: nil,
                distanceMeters: distance,
                structureHeader: header,
                structureBlockIndex: blockIndex,
                supersetPartner: nil
            )
        }
        guard let reps = logbookReps(for: exercise) else { return nil }
        let sets = logbookSetCount(exercise: exercise, block: block)
        return PlannedItem(
            entryID: entryID,
            ghostKey: ghostKey,
            name: exercise.name,
            sets: sets,
            reps: reps,
            weightKg: kilograms(from: exercise.load),
            loggingKind: .strength,
            durationSeconds: nil,
            calories: nil,
            distanceMeters: nil,
            structureHeader: header,
            structureBlockIndex: blockIndex,
            supersetPartner: nil
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func uniqueEntryID(
        preferred: String,
        ghostKey: String,
        blockIndex: Int,
        stationIndex: Int,
        occurrence: Int,
        used: inout Set<String>
    ) -> String {
        let candidates = [
            preferred,
            "\(ghostKey)_b\(blockIndex)_s\(stationIndex)",
            "\(ghostKey)_b\(blockIndex)_s\(stationIndex)_o\(occurrence)",
            "\(ghostKey)_o\(occurrence)_\(UUID().uuidString.prefix(8))"
        ]
        for candidate in candidates where !candidate.isEmpty && used.insert(candidate).inserted {
            return candidate
        }
        let fallback = "\(ghostKey)_\(UUID().uuidString)"
        used.insert(fallback)
        return fallback
    }

    /// Timed / distance prescriptions, or named cardio machines (jump rope, bike, …)
    /// even when the library row still carries a junk `1` rep.
    private static func isMetricStation(_ exercise: Exercise) -> Bool {
        if exercise.durationSeconds != nil { return true }
        if let distance = exercise.distance, distance > 0 { return true }
        let prescription = PrescriptionFormatter.effective(from: exercise)
        switch prescription.primary {
        case .duration, .distance, .calories:
            return true
        case .reps, .repsRange, .open, .none:
            break
        }
        guard WorkoutSportHonesty.modalityChipKind(forExerciseName: exercise.name) == .cardio else {
            return false
        }
        // Cardio name with no real strength prescription → TIME/CAL strip.
        let reps = BlockToIntervalConverter.parseReps(exercise.reps)
        let sets = exercise.sets ?? 1
        if exercise.load != nil, reps >= 3 { return false }
        if sets > 1, reps >= 3 { return false }
        return true
    }

    /// Working-set rows for the grid. Single-station nil `sets` → `block.rounds`
    /// (detail "6 ROUNDS" / "6 × 8"). Multi-station: one row per round.
    private static func logbookSetCount(exercise: Exercise, block: Block) -> Int {
        if let sets = exercise.sets, sets > 0 { return sets }
        return max(1, block.rounds)
    }

    /// Parsed rep target, or `0` for open / empty Rx (`N × OPEN`). Never drop the station.
    private static func logbookReps(for exercise: Exercise) -> Int? {
        let parsed = BlockToIntervalConverter.parseReps(exercise.reps)
        if parsed > 0 { return parsed }
        // AMRAP / empty-reps / open — keep the row with no invented target.
        return 0
    }

    private static func isWarmupOrCooldown(_ block: Block) -> Bool {
        guard let label = block.label?.lowercased() else { return false }
        return label.contains("warm") || label.contains("cool")
    }

    private static func structureHeader(for block: Block, multiStation: Bool) -> String? {
        let rounds = max(block.rounds, 1)
        if multiStation, rounds > 1 {
            switch block.structure {
            case .superset: return "SUPERSET · \(rounds) ROUNDS"
            default: return "CIRCUIT · \(rounds) ROUNDS"
            }
        }
        if !multiStation, rounds > 1 {
            return "\(rounds) ROUNDS"
        }
        return nil
    }

    private static func kilograms(from load: ExerciseLoad?) -> Double? {
        guard let load else { return nil }
        let unit = load.unit.lowercased()
        if unit.contains("lb") {
            return WeightUnitMath.kilograms(fromDisplay: load.value, unit: .lbs)
        }
        return load.value
    }

    private static func subtitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE · HH:mm"
        return formatter.string(from: date).uppercased()
    }
}
