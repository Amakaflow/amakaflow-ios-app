//
//  StructureClarifyFixtures.swift
//  AmakaFlow
//
//  AMA-2305 — ADR-017 ground-truth fixture for reel DMqEsenN6Dl + Describe utterances.
//

import Foundation

enum StructureClarifyFixtures {
    /// Verbatim caption from ADR-017 / AMA-2306.
    static let dmqCaption = """
    Warm up: Ski 1000m easy pace  2 rounds  - Press ups x5 - Pull ups x5
    Workout:
    4 rounds - 3 mins rest - Bench Press x 8 reps x - Pull Ups x 8 reps
    4 rounds - 90s rest  - Single Arm Incline Press x 8 reps  x - Single Arm Incline Row x 8 reps
    - Incline Bicep Curls 3 x 12 reps. 60s rest
    5 rounds for time  - Ski 300m - Farmers Walk 40m
    """

    static let dmqExercises: [StructureExerciseModel] = [
        .init(name: "Ski 1000m", distanceM: 1000, notes: "easy pace"),
        .init(name: "Press ups", sets: 2, reps: 5),
        .init(name: "Pull ups", sets: 2, reps: 5),
        .init(name: "Bench Press", reps: 8),
        .init(name: "Pull Ups", reps: 8),
        .init(name: "Single Arm Incline Press", reps: 8),
        .init(name: "Single Arm Incline Row", reps: 8),
        .init(name: "Incline Bicep Curls", sets: 3, reps: 12, restSec: 60),
        .init(name: "Ski 300m", distanceM: 300),
        .init(name: "Farmers Walk", distanceM: 40)
    ]

    static let dmqSuggestions: [StructureSuggestionModel] = [
        .init(
            type: .warmup,
            label: "Warm-up",
            rounds: 2,
            exerciseNames: ["Ski 1000m", "Press ups", "Pull ups"],
            exerciseIndices: [0, 1, 2],
            structureSource: .inferred
        ),
        .init(
            type: .superset,
            label: "Bench + Pull Ups",
            rounds: 4,
            restSec: 180,
            exerciseNames: ["Bench Press", "Pull Ups"],
            exerciseIndices: [3, 4],
            structureSource: .inferred
        ),
        .init(
            type: .superset,
            label: "Incline Press + Row",
            rounds: 4,
            restSec: 90,
            exerciseNames: ["Single Arm Incline Press", "Single Arm Incline Row"],
            exerciseIndices: [5, 6],
            structureSource: .inferred
        ),
        .init(
            type: .circuit,
            label: "Finisher",
            rounds: 5,
            exerciseNames: ["Ski 300m", "Farmers Walk"],
            exerciseIndices: [8, 9],
            structureSource: .inferred
        )
    ]

    static var dmqSuggestResult: StructureSuggestResult {
        StructureSuggestResult(
            exercises: dmqExercises,
            suggestions: dmqSuggestions,
            blocks: []
        )
    }

    /// Ambiguous “every minute” caption → inferred EMOM suggestion (confirm → user_confirmed).
    static let emomExercises: [StructureExerciseModel] = [
        .init(name: "Power Clean", reps: 5),
        .init(name: "Push Press", reps: 8),
        .init(name: "Pull Ups", reps: 6)
    ]

    static var emomSuggestResult: StructureSuggestResult {
        StructureSuggestResult(
            exercises: emomExercises,
            suggestions: [
                .init(
                    type: .emom,
                    label: "EMOM 10",
                    rounds: 10,
                    exerciseNames: emomExercises.map(\.name),
                    exerciseIndices: [0, 1, 2],
                    structureSource: .inferred
                )
            ],
            blocks: []
        )
    }

    /// After Describe: "curls go after the incline pair, finisher is a circuit x5"
    static var dmqNoteAppliedBlocks: [StructureBlockModel] {
        [
            StructureBlockModel(
                type: .warmup,
                label: "Warm-up",
                rounds: 2,
                exercises: Array(dmqExercises.prefix(3)),
                structureSource: .inferred
            ),
            StructureBlockModel(
                type: .superset,
                label: "Bench + Pull Ups",
                rounds: 4,
                restSec: 180,
                exercises: [dmqExercises[3], dmqExercises[4]],
                structureSource: .inferred
            ),
            StructureBlockModel(
                type: .superset,
                label: "Incline Press + Row + Curls",
                rounds: 4,
                restSec: 90,
                exercises: [dmqExercises[5], dmqExercises[6], dmqExercises[7]],
                structureSource: .userNote
            ),
            StructureBlockModel(
                type: .circuit,
                label: "Finisher",
                rounds: 5,
                exercises: [dmqExercises[8], dmqExercises[9]],
                structureSource: .userNote
            )
        ]
    }

    static var suggestResponseJSON: Data {
        // swiftlint:disable:next force_try
        try! StructureJSON.encoder.encode(dmqSuggestResult)
    }

    static var applyNoteResponseJSON: Data {
        // swiftlint:disable:next force_try
        try! StructureJSON.encoder.encode(ApplyStructureResult(blocks: dmqNoteAppliedBlocks))
    }
}
