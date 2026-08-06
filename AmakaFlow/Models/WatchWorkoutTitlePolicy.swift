//
//  WatchWorkoutTitlePolicy.swift
//  AmakaFlow
//
//  Shared rules for Apple schedule + Garmin queue titles:
//  same display name is one slot; intentional copies end with " (N)".
// CI: keep this file in the PR path filter so Actions re-runs after outages.
//

import Foundation

enum WatchWorkoutTitlePolicy {
    static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when the title is an intentional duplicate copy (`Engine EMOM (1)`).
    static func isIntentionalCopy(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4,
              trimmed.hasSuffix(")"),
              let openParen = trimmed.lastIndex(of: "("),
              openParen > trimmed.startIndex,
              trimmed[trimmed.index(before: openParen)] == " "
        else { return false }

        let digitsStart = trimmed.index(after: openParen)
        let digitsEnd = trimmed.index(before: trimmed.endIndex)
        guard digitsStart < digitsEnd else { return false }
        let digits = trimmed[digitsStart..<digitsEnd]
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    /// Exact normalized title match — `Foo` and `Foo (1)` are different workouts.
    static func isSameScheduledTitle(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }
}
