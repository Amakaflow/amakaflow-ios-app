//
//  LogbookGhostLookup.swift
//  AmakaFlow
//
//  Ghost lookups that are pure functions of an entry — they never touched
//  view-model state, so they did not belong on the view model. Split out when
//  AMA-2462's tracked-field control pushed LogbookViewModel.swift past the
//  SwiftLint file_length limit.
//

import Foundation

enum LogbookGhostLookup {
    static func stored(for entry: LogbookExerciseEntry, setIndex: Int) -> LogbookGhost? {
        if let idx = entry.sets.firstIndex(where: { $0.index == setIndex }),
           idx < entry.ghosts.count {
            return entry.ghosts[idx]
        }
        return entry.ghosts.last
    }

    static func previousFilledSet(in entry: LogbookExerciseEntry, before setIndex: Int) -> SetActual? {
        entry.sets
            .filter { set in
                set.index < setIndex
                    && (
                        set.weightKg != nil
                            || set.reps != nil
                            || set.durationSeconds != nil
                            || set.calories != nil
                            || set.distanceMeters != nil
                    )
            }
            .max { $0.index < $1.index }
    }
}
