//
//  WorkoutCaptionPresentation.swift
//  AmakaFlow
//
//  AMA-2395 — a social caption is provenance, not the page body. The collapsed
//  FROM THE CREATOR card shows the readable sentence; hashtags and bare CTAs
//  ("Save it and give it a go!", "Double tap & Save") only appear once the
//  reader asks for More.
//
//  Display layer ONLY — `collapsed` never replaces the stored caption, and
//  `expanded` is always the untouched original.
//

import Foundation

enum WorkoutCaptionPresentation {

    /// The untouched caption, shown when the card is expanded.
    static func expanded(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The readable version: hashtag-only lines and bare calls-to-action
    /// removed, trailing hashtag runs trimmed off the end of real sentences.
    static func collapsed(_ raw: String?) -> String {
        let source = expanded(raw)
        guard !source.isEmpty else { return "" }

        let kept = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map(stripTrailingHashtags)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !isCallToAction(trimmed)
            }

        let joined = kept.joined(separator: " ")
        return joined
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the collapsed view hides something, so the card earns a
    /// More/Less toggle instead of showing a dead control.
    static func hasHiddenDetail(_ raw: String?) -> Bool {
        let full = expanded(raw)
        guard !full.isEmpty else { return false }
        // Compare against the same space-joined shape `collapsed` produces —
        // otherwise plain multiline copy looks like it is hiding something.
        let normalised = full
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed(raw) != normalised
    }

    /// The creator's own time when the caption states it ("My time: 57.53"),
    /// normalised to `57:53`. Shown next to our estimate as an honest anchor —
    /// never used to overwrite the estimate.
    static func creatorTime(in raw: String?) -> String? {
        let text = expanded(raw)
        guard !text.isEmpty else { return nil }
        let pattern = #"\b(?:my |finished in |took me |time)[^\n\d]{0,12}(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }

        let parts = (1..<match.numberOfRanges).compactMap { index -> String? in
            guard let partRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[partRange])
        }
        guard parts.count >= 2 else { return nil }
        return parts.joined(separator: ":")
    }

    // MARK: - Helpers

    /// `500m Ski · 500m Row #erg #workout` → `500m Ski · 500m Row`.
    /// A hashtag mid-sentence is left alone — only a run at the end goes.
    private static func stripTrailingHashtags(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"(\s*#[\p{L}\p{N}_]+)+\s*$"#,
            with: "",
            options: .regularExpression
        )
    }

    private static let callToActionPatterns = [
        #"save it and give it a go"#,
        #"double\s*tap"#,
        #"^save (this|it)\b"#,
        #"^like\b.*\bsave\b"#,
        #"tag a (friend|mate)"#,
        #"link in bio"#,
        #"^follow (me|us|for)\b"#,
        #"^(comment|drop)\b.*\bbelow\b"#,
        #"^share (this|it)\b"#,
        #"turn on post notifications"#
    ]

    private static func isCallToAction(_ line: String) -> Bool {
        // A line that is nothing but hashtags/emoji is already gone by here;
        // this catches the "engagement bait" sentences that follow the workout.
        let lowered = line.lowercased()
        return callToActionPatterns.contains { pattern in
            lowered.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
