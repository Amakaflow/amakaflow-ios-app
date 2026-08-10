//
//  WorkoutDurationEstimator.swift
//  AmakaFlow
//
//  AMA-2395 — pure duration estimator from workout structure.
//  Timed steps are exact; distances use WorkoutPaceTable; reps use
//  reps×3s + 15s setup + rest defaults. Structure always wins over a
//  stored `workout.duration` when there is anything measurable.
//

import Foundation

enum WorkoutDurationEstimator {
    static let secondsPerRep = 3
    static let setupSecondsPerSet = 15
    static let defaultRestSeconds = 60
    static let heavyRestSeconds = 90
    static let heavyRepThreshold = 6
    static let transitionPadding = 0.05
    /// When sets exist but no timed / distance / reps target: 1 min work + 1 min rest per set.
    static let undefinedSetWorkSeconds = 60
    static let undefinedSetRestSeconds = 60

    static func estimate(for workout: Workout) -> WorkoutDurationEstimate {
        estimate(blocks: workout.blocks, storedDurationSeconds: workout.duration)
    }

    static func estimate(blocks: [Block], storedDurationSeconds: Int = 0) -> WorkoutDurationEstimate {
        let workBlocks = blocks.filter { !$0.exercises.isEmpty }
        guard !workBlocks.isEmpty else {
            return fallbackStored(storedDurationSeconds)
        }

        var perExercise: [WorkoutExerciseDuration] = []
        var perSection: [WorkoutSectionDuration] = []
        var totalSec = 0
        var activeSec = 0
        var anyEstimate = false
        var openNames: [String] = []
        var flags = SignalFlags()

        for block in workBlocks {
            let blockResult = estimateBlock(block)
            perExercise.append(contentsOf: blockResult.exercises)
            openNames.append(contentsOf: blockResult.openNames)
            flags.merge(blockResult.flags)

            var sectionSec = blockResult.seconds
            var sectionEstimate = blockResult.isEstimate
            // Transition padding is itself a guess — only on multi-station
            // estimated blocks (circuits / chippers). All-timed stays exact;
            // straight strength lists don't get invented station-change time.
            if sectionEstimate, isMultiStation(block) {
                sectionSec = Int((Double(sectionSec) * (1.0 + transitionPadding)).rounded())
            }
            if sectionEstimate { anyEstimate = true }

            perSection.append(
                WorkoutSectionDuration(
                    blockId: block.id,
                    seconds: sectionSec,
                    isEstimate: sectionEstimate
                )
            )
            totalSec += sectionSec
            activeSec += blockResult.activeSeconds
        }

        if totalSec == 0, openNames.isEmpty {
            return fallbackStored(storedDurationSeconds)
        }

        return WorkoutDurationEstimate(
            totalSec: totalSec,
            activeSec: max(0, activeSec),
            isEstimate: anyEstimate,
            perSection: perSection,
            perExercise: perExercise,
            basisNote: basisNote(flags: flags, openNames: openNames, isEstimate: anyEstimate),
            activeSublabel: activeSublabel(flags: flags, isEstimate: anyEstimate)
        )
    }
}
