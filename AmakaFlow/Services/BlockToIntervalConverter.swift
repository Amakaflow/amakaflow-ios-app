import Foundation

/// Converts structured Block models into flat WorkoutInterval arrays
/// suitable for playback and display in the workout runner.
enum BlockToIntervalConverter {

    // MARK: - Public API

    /// Convert an array of blocks into a flat interval list.
    static func flatten(_ blocks: [Block]) -> [WorkoutInterval] {
        blocks.flatMap { convert(block: $0) }
    }

    /// Convert a single block into its interval representation.
    static func convert(block: Block) -> [WorkoutInterval] {
        let isWarmup  = block.label.map { $0.lowercased().contains("warm") } ?? false
        let isCooldown = block.label.map { $0.lowercased().contains("cool") } ?? false

        switch block.structure {
        case .tabata:
            return buildTabataIntervals(block: block)
        case .emom:
            return buildEmomIntervals(block: block)
        default:
            break
        }

        let exerciseIntervals = buildExerciseIntervals(
            block: block,
            isWarmup: isWarmup,
            isCooldown: isCooldown
        )

        // Multi-round superset / circuit / amrap → wrap in repeat
        let isMultiRound = block.structure == .superset
            || block.structure == .circuit
            || block.structure == .amrap
        if isMultiRound && block.rounds > 1 {
            var roundIntervals = exerciseIntervals
            // Add rest at end of round (between rounds) for multi-round blocks
            if let restSec = block.restBetweenSeconds {
                roundIntervals.append(.rest(seconds: restSec))
            }
            return [.repeat(reps: block.rounds, intervals: roundIntervals)]
        }

        return exerciseIntervals
    }

    // MARK: - Specialised structure builders

    /// Tabata: 20s work / 10s rest per exercise, wrapped in repeat for rounds.
    private static func buildTabataIntervals(block: Block) -> [WorkoutInterval] {
        var roundIntervals: [WorkoutInterval] = []
        for exercise in block.exercises {
            let target = exercise.notes ?? exercise.name
            roundIntervals.append(.time(seconds: 20, target: target))
            roundIntervals.append(.rest(seconds: 10))
        }
        let rounds = max(block.rounds, 1)
        if rounds > 1 {
            return [.repeat(reps: rounds, intervals: roundIntervals)]
        }
        return roundIntervals
    }

    /// EMOM: each exercise fills one minute (or block-level period via restBetweenSeconds).
    private static func buildEmomIntervals(block: Block) -> [WorkoutInterval] {
        let period = block.restBetweenSeconds ?? 60 // default 60s EMOM period
        var roundIntervals: [WorkoutInterval] = []
        for exercise in block.exercises {
            let target = exercise.notes ?? exercise.name
            roundIntervals.append(.time(seconds: period, target: target))
        }
        let rounds = max(block.rounds, 1)
        if rounds > 1 {
            return [.repeat(reps: rounds, intervals: roundIntervals)]
        }
        return roundIntervals
    }

    // MARK: - Private helpers

    private static func buildExerciseIntervals(
        block: Block,
        isWarmup: Bool,
        isCooldown: Bool
    ) -> [WorkoutInterval] {
        var result: [WorkoutInterval] = []

        for (index, exercise) in block.exercises.enumerated() {
            let interval = makeInterval(
                exercise: exercise,
                isWarmup: isWarmup,
                isCooldown: isCooldown
            )
            result.append(interval)

            // Insert rest between exercises only when there's an actual rest value.
            // Nil rest would emit .rest(seconds: nil) which renders as manual/indefinite rest.
            let isLast = index == block.exercises.count - 1
            if !isLast, let restSecs = exercise.restSeconds ?? block.restBetweenSeconds {
                result.append(.rest(seconds: restSecs))
            }
        }

        return result
    }

    private static func makeInterval(
        exercise: Exercise,
        isWarmup: Bool,
        isCooldown: Bool
    ) -> WorkoutInterval {
        // Distance-based exercise
        if let distance = exercise.distance {
            let meters = Int(distance)
            return .distance(meters: meters, target: exercise.notes)
        }

        // Duration-based exercise
        if let duration = exercise.durationSeconds {
            if isWarmup {
                return .warmup(seconds: duration, target: exercise.notes)
            } else if isCooldown {
                return .cooldown(seconds: duration, target: exercise.notes)
            } else {
                return .time(seconds: duration, target: exercise.notes)
            }
        }

        // Rep-based exercise (default path)
        let repsInt = parseReps(exercise.reps)
        let loadStr = formatLoad(exercise.load)
        return .reps(
            sets: exercise.sets,
            reps: repsInt,
            name: exercise.name,
            load: loadStr,
            restSec: exercise.restSeconds,
            followAlongUrl: nil
        )
    }

    // MARK: - Parsing utilities

    /// Parse a reps string into Int. Handles ranges like "8-10" (takes upper bound).
    /// Returns 0 if the string cannot be parsed.
    static func parseReps(_ repsString: String?) -> Int {
        guard let repsString = repsString, !repsString.isEmpty else { return 0 }

        // Range like "8-10" → take the higher end
        if repsString.contains("-") {
            let parts = repsString.split(separator: "-")
            if let last = parts.last, let value = Int(last.trimmingCharacters(in: .whitespaces)) {
                return value
            }
        }

        // Plain integer or integer with trailing text (e.g. "10 reps")
        let digits = repsString.prefix(while: { $0.isNumber || $0 == " " })
            .trimmingCharacters(in: .whitespaces)
        return Int(digits) ?? 0
    }

    /// Format an ExerciseLoad into a display string for WorkoutInterval.
    private static func formatLoad(_ load: ExerciseLoad?) -> String? {
        guard let load = load else { return nil }
        if load.unit == "bodyweight" { return "BW" }
        let valStr = load.value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(load.value))
            : String(load.value)
        return "\(valStr)\(load.unit)"
    }
}
