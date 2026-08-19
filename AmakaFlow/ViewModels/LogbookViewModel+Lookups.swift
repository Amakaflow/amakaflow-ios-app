//
//  LogbookViewModel+Lookups.swift
//  AmakaFlow
//
//  Read-only lookups into the draft. They mutate nothing, so they belong
//  beside the view model rather than inside it — and moving them keeps
//  LogbookViewModel.swift under the SwiftLint file_length limit as AMA-2473
//  adds "log the session as written".
//

import Foundation

extension LogbookViewModel {
    func ghost(for exerciseID: String, setIndex: Int) -> LogbookGhost? {
        effectiveLastReference(exerciseID: exerciseID, setIndex: setIndex)
    }

    func focusedSet() -> (entry: LogbookExerciseEntry, set: SetActual)? {
        guard let focus = wheelFocus,
              let entry = draft.entries.first(where: { $0.id == focus.exerciseID }),
              let set = entry.sets.first(where: {
                  $0.index == focus.setIndex && $0.isWarmup == focus.isWarmup
              }) else {
            return nil
        }
        return (entry, set)
    }
}
