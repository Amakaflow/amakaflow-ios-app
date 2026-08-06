//
//  WatchWorkoutTitlePolicy.swift
//  AmakaFlow
//
//  Shared rules for Apple schedule + Garmin queue titles:
//  same display name is one slot; intentional copies end with " (N)".
//

import Foundation

enum WatchWorkoutTitlePolicy {
    /// Matches a trailing copy marker like " (1)" / " (12)" after the base name.
    private static let intentionalCopySuffix = try! NSRegularExpression(
        pattern: #" \(\d+\)$"#
    )

    static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when the title is an intentional duplicate copy (`Engine EMOM (1)`).
    static func isIntentionalCopy(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return intentionalCopySuffix.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    /// Exact normalized title match — `Foo` and `Foo (1)` are different workouts.
    static func isSameScheduledTitle(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalized(lhs)
        let b = normalized(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b
    }
}
