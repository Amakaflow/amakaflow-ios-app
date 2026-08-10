//
//  ActualsMapCTAState.swift
//  AmakaFlow
//
//  AMA-2396 A1: Map page v3 pinned CTA state machine
//  (Keep-as-is ↔ Match to "<name>").
//

import Foundation

enum ActualsMapCTAKind: Equatable {
    case keepAsIs
    case match(title: String)
}

enum ActualsMapCTAState {
    /// Nothing selected → Keep as "<activity>" — done
    /// Match selected → Match to "<name>"
    /// Deselect reverts to keep-as-is.
    static func kind(
        selectedMatchTitle: String?,
        activityTitle: String
    ) -> ActualsMapCTAKind {
        if let selectedMatchTitle, !selectedMatchTitle.isEmpty {
            return .match(title: selectedMatchTitle)
        }
        return .keepAsIs
    }

    static func label(
        selectedMatchTitle: String?,
        activityTitle: String
    ) -> String {
        switch kind(selectedMatchTitle: selectedMatchTitle, activityTitle: activityTitle) {
        case .keepAsIs:
            return ActualsCopy.mapKeepAsDoneCTA(title: activityTitle)
        case .match(let title):
            return ActualsCopy.mapMatchToCTA(title: title)
        }
    }

    static func isMatchSelected(_ selectedMatchTitle: String?) -> Bool {
        guard let selectedMatchTitle else { return false }
        return !selectedMatchTitle.isEmpty
    }
}
