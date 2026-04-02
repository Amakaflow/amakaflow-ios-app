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

        let exerciseIntervals = buildExerciseIntervals(
            block: block,
            isWarmup: isWarmup,
            isCooldown: isCooldown
        )

        // Multi-round superset / circuit → wrap in repeat
        if (block.structure == .superset || block.structure == .circuit) && block.rounds > 1 {
            return [.repeat(reps: block.rounds, intervals: exerciseIntervals)]
        }

        return exerciseIntervals
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

            // Insert rest between exercises, not after the last one
            let isLast = index == block.exercises.count - 1
            if !isLast {
                let restSecs = exercise.restSeconds ?? block.restBetweenSeconds
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
