//
//  LogbookSeeding.swift
//  AmakaFlow
//
//  AMA-2426: seed logbook entries from a library workout plan or blank.
//

import Foundation

enum LogbookSeeding {
    /// Prefill from a Library workout's intervals.
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
            state: .pending,
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
        let planned = flattenIntervals(workout.intervals)
        guard !planned.isEmpty else {
            return blankDraft(mode: .after).entries
        }

        return planned.map { item in
            let key = ActualsGhostFeed.exerciseKey(forName: item.name)
            let entryID = item.structureBlockIndex.map { "\(key)#\($0)" } ?? key
            let lastActual = try? ghostLookup?.latestActual(exerciseKey: key)
            let loadPlan = loadPlanLookup?(entryID)
            let setCount = max(item.sets, loadPlan?.count ?? 0, 1)
            let sets: [SetActual] = (1...setCount).map { index in
                if let target = loadPlan?.first(where: { $0.index == index }) {
                    return SetActual(
                        index: index,
                        isWarmup: target.isWarmup,
                        weightKg: target.weightKg,
                        reps: target.reps,
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
                id: entryID,
                name: item.name,
                planned: plannedModel,
                sets: sets,
                ghosts: ghosts,
                structureHeader: item.structureHeader,
                structureBlockIndex: item.structureBlockIndex,
                supersetPartner: item.supersetPartner
            )
        }
    }

    // MARK: - Private

    private struct PlannedItem {
        var name: String
        var sets: Int
        var reps: Int
        var weightKg: Double?
        var structureHeader: String?
        var structureBlockIndex: Int?
        var supersetPartner: String?
    }

    private static func flattenIntervals(_ intervals: [WorkoutInterval]) -> [PlannedItem] {
        var result: [PlannedItem] = []
        var blockIndex = 0
        for interval in intervals {
            switch interval {
            case .reps(let sets, let reps, let name, let load, _, _):
                let resolved = Workout.resolveLegacyLoadAndInstruction(from: load)
                let weightKilograms = kilograms(from: resolved.load)
                result.append(
                    PlannedItem(
                        name: name,
                        sets: max(sets ?? 1, 1),
                        reps: reps,
                        weightKg: weightKilograms,
                        structureHeader: nil,
                        structureBlockIndex: blockIndex,
                        supersetPartner: nil
                    )
                )
                blockIndex += 1
            case .repeat(let times, let children):
                let nested = flattenIntervals(children)
                let header = nested.count > 1 ? "SUPERSET · \(max(times, 1)) ROUNDS" : nil
                for item in nested {
                    var copy = item
                    copy.structureHeader = header ?? item.structureHeader
                    copy.structureBlockIndex = blockIndex
                    result.append(copy)
                }
                if nested.count == 2 {
                    let last = result.count
                    if last >= 2 {
                        result[last - 2].supersetPartner = result[last - 1].name
                        result[last - 1].supersetPartner = result[last - 2].name
                    }
                }
                blockIndex += 1
            default:
                continue
            }
        }
        return collapseConsecutive(result)
    }

    private static func kilograms(from load: ExerciseLoad?) -> Double? {
        guard let load else { return nil }
        let unit = load.unit.lowercased()
        if unit.contains("lb") {
            return WeightUnitMath.kilograms(fromDisplay: load.value, unit: .lbs)
        }
        return load.value
    }

    private static func collapseConsecutive(_ items: [PlannedItem]) -> [PlannedItem] {
        var collapsed: [PlannedItem] = []
        for item in items {
            if let last = collapsed.last,
               last.name.caseInsensitiveCompare(item.name) == .orderedSame,
               last.structureBlockIndex == item.structureBlockIndex {
                collapsed[collapsed.count - 1].sets += item.sets
            } else {
                collapsed.append(item)
            }
        }
        return collapsed
    }

    private static func subtitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE · HH:mm"
        return formatter.string(from: date).uppercased()
    }
}
