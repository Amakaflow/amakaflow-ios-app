//
//  LibraryPasteRouter.swift
//  AmakaFlow
//
//  AMA-2297: Library FAB / "Paste a link" routes social URLs to workout import,
//  not knowledge bookmark save.
//

import Foundation
import UIKit

enum LibraryAddDestination: Identifiable, Equatable {
    case knowledge
    case socialImport(url: String?, platform: SocialImportPlatform?)

    var id: String {
        switch self {
        case .knowledge:
            return "knowledge"
        case .socialImport(let url, let platform):
            return "social-\(platform?.rawValue ?? "any")-\(url ?? "")"
        }
    }
}

enum LibraryPasteRouter {
    /// Peek clipboard and decide Library add destination.
    /// Social hosts (IG / TikTok / YouTube) → workout import; everything else → knowledge.
    static func destination(clipboardString: String? = UIPasteboard.general.string) -> LibraryAddDestination {
        guard let candidate = firstHTTPURL(in: clipboardString),
              SocialImportPlatform.isWorkoutImportURL(candidate) else {
            return .knowledge
        }
        let normalized = SocialImportPlatform.normalizeForIngest(candidate)
        return .socialImport(
            url: normalized,
            platform: SocialImportPlatform.detect(from: normalized)
        )
    }

    /// Extract first http(s) URL from clipboard text (IG often embeds URL in caption text).
    static func firstHTTPURL(in text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = detector.firstMatch(in: trimmed, options: [], range: range),
               let urlRange = Range(match.range, in: trimmed) {
                let found = String(trimmed[urlRange])
                if found.lowercased().hasPrefix("http") {
                    return found
                }
            }
        }

        return AddToLibraryViewModel.normalizedURL(from: trimmed)?.absoluteString
    }
}
