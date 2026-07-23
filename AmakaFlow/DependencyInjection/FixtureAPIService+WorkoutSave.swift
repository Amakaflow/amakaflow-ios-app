//
//  FixtureAPIService+WorkoutSave.swift
//  AmakaFlow
//
//  Fixture workout save (split for SwiftLint file_length / type_body_length).
//

#if DEBUG
import Foundation

extension FixtureAPIService {
    // MARK: - Workout Save (AMA-1231)

    func saveWorkout(_ request: WorkoutSaveRequest) async throws -> Workout {
        print("[FixtureAPIService] Stub: saveWorkout -> fixture workout (source=\(request.source ?? "nil"))")
        let source = request.source.flatMap(WorkoutSource.init(rawValue:)) ?? .manual
        let workoutId = request.workoutId ?? "fixture-saved-\(UUID().uuidString)"
        let saved: Workout
        if let blocks = request.blocks, !blocks.isEmpty {
            let mappedBlocks = blocks.map { block in
                Block(
                    label: block.label,
                    structure: WorkoutLibraryDetailStore.blockStructure(from: block.type),
                    rounds: max(1, block.rounds),
                    exercises: block.exercises.map { $0.toExercise() },
                    restBetweenSeconds: block.restSec
                )
            }
            saved = Workout(
                id: workoutId,
                name: request.name,
                sport: WorkoutSport(rawValue: request.sport) ?? .strength,
                duration: 0,
                blocks: mappedBlocks,
                description: request.description,
                source: source,
                sourceUrl: request.sourceUrl,
                creatorName: request.creatorName,
                createdAt: Date()
            )
        } else {
            let intervals = request.intervals.compactMap(WorkoutLibraryDetailStore.interval(from:))
            saved = Workout(
                id: workoutId,
                name: request.name,
                sport: WorkoutSport(rawValue: request.sport) ?? .strength,
                duration: 0,
                intervals: intervals,
                source: source,
                sourceUrl: request.sourceUrl,
                creatorName: request.creatorName,
                createdAt: Date()
            )
        }
        upsertFixtureWorkout(saved)
        return saved
    }
}
#endif
