//
//  WorkoutCaptionPresentation.swift
//  AmakaFlow
//
//  AMA-2395 — display-only caption collapse for the FROM THE CREATOR / NOTES card.
//  Never mutates stored workout description.
//

import Foundation

struct WorkoutCaptionPresentation: Equatable, Sendable {
    /// Raw caption always available when expanded.
    let expanded: String
    /// Hashtags + bare CTA lines stripped for the collapsed 2-line preview.
    let collapsed: String
    let hasHiddenDetail: Bool

    static func present(_ raw: String?) -> WorkoutCaptionPresentation? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collapsed = collapse(trimmed)
        let collapsedTrimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutCaptionPresentation(
            expanded: trimmed,
            collapsed: collapsedTrimmed.isEmpty ? trimmed : collapsedTrimmed,
            hasHiddenDetail: collapsedTrimmed != trimmed
                && !collapsedTrimmed.isEmpty
        )
    }

    /// Pull a creator-stated finish time out of the caption when present
    /// (`My time: 57.53`, `1:36:10`, etc.) for the TIME card footnote.
    static func creatorTimeLabel(from raw: String?) -> String? {
        guard let raw else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for regex in creatorTimeRegexes {
            guard let match = regex.firstMatch(in: raw, range: range),
                  match.numberOfRanges >= 3,
                  let firstR = Range(match.range(at: 1), in: raw),
                  let secondR = Range(match.range(at: 2), in: raw)
            else { continue }
            let first = String(raw[firstR])
            let second = String(raw[secondR])
            if match.numberOfRanges >= 4,
               let thirdR = Range(match.range(at: 3), in: raw),
               match.range(at: 3).location != NSNotFound {
                let third = String(raw[thirdR])
                return "\(first):\(second):\(third)"
            }
            return "\(first):\(second)"
        }
        return nil
    }

    /// Compiled once — `timeCard` calls this on every detail render.
    private static let creatorTimeRegexes: [NSRegularExpression] = {
        let patterns = [
            // H:MM:SS first so 1:36:10 is not truncated to 1:36.
            #"(?i)my\s+time\s*:?\s*(\d{1,2})[.:](\d{2})[.:](\d{2})"#,
            #"(?i)(?:finished|finish)\s*(?:in)?\s*(\d{1,2})[.:](\d{2})[.:](\d{2})"#,
            #"(?i)\btime\s*:?\s*(\d{1,2})[.:](\d{2})[.:](\d{2})"#,
            #"(?i)my\s+time\s*:?\s*(\d{1,2})[.:](\d{2})"#,
            #"(?i)(?:finished|finish)\s*(?:in)?\s*(\d{1,2})[.:](\d{2})"#,
            #"(?i)\btime\s*:?\s*(\d{1,2})[.:](\d{2})"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static func collapse(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let filtered = lines.filter { line in
            if isHashtagOnly(line) { return false }
            if isCTALine(line) { return false }
            return true
        }

        let joined = (filtered.isEmpty ? lines : filtered).joined(separator: " ")
        return stripTrailingHashtags(joined)
    }

    private static func isHashtagOnly(_ line: String) -> Bool {
        let tokens = line.split { $0.isWhitespace }
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy { $0.hasPrefix("#") }
    }

    private static func isCTALine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let needles = [
            "save it and give it a go",
            "double tap",
            "double tap & save",
            "double tap and save",
            "save this workout",
            "tag a friend",
            "link in bio"
        ]
        return needles.contains { lowered.contains($0) }
    }

    private static func stripTrailingHashtags(_ text: String) -> String {
        var tokens = text.split { $0.isWhitespace }.map(String.init)
        while let last = tokens.last, last.hasPrefix("#") {
            tokens.removeLast()
        }
        return tokens.joined(separator: " ")
    }
}
