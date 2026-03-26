//
//  PlatformDetector.swift
//  AmakaFlowShare
//
//  Detects which platform a URL belongs to (YouTube, Instagram, TikTok, Pinterest, etc.)
//  AMA-1257: iOS Share Extension — one-tap workout import from any app
//

import Foundation

/// Represents a detected content platform with display metadata
struct DetectedPlatform: Equatable {
    let name: String
    let iconSystemName: String
    let accentColorHex: String

    static let youtube = DetectedPlatform(name: "YouTube", iconSystemName: "play.rectangle.fill", accentColorHex: "#FF0000")
    static let instagram = DetectedPlatform(name: "Instagram", iconSystemName: "camera.fill", accentColorHex: "#E4405F")
    static let tiktok = DetectedPlatform(name: "TikTok", iconSystemName: "music.note", accentColorHex: "#000000")
    static let pinterest = DetectedPlatform(name: "Pinterest", iconSystemName: "pin.fill", accentColorHex: "#E60023")
    static let twitter = DetectedPlatform(name: "X / Twitter", iconSystemName: "at", accentColorHex: "#1DA1F2")
    static let facebook = DetectedPlatform(name: "Facebook", iconSystemName: "person.2.fill", accentColorHex: "#1877F2")
    static let reddit = DetectedPlatform(name: "Reddit", iconSystemName: "bubble.left.fill", accentColorHex: "#FF4500")
    static let safari = DetectedPlatform(name: "Web Link", iconSystemName: "safari.fill", accentColorHex: "#007AFF")
}

/// Detects the source platform from a URL string
enum PlatformDetector {

    /// Detect the platform for a given URL string.
    /// Returns `.safari` as a fallback for unrecognized domains.
    static func detect(from urlString: String) -> DetectedPlatform {
        let lowered = urlString.lowercased()

        // YouTube (youtube.com, youtu.be, m.youtube.com)
        if lowered.contains("youtube.com") || lowered.contains("youtu.be") {
            return .youtube
        }

        // Instagram (instagram.com, instagr.am)
        if lowered.contains("instagram.com") || lowered.contains("instagr.am") {
            return .instagram
        }

        // TikTok (tiktok.com, vm.tiktok.com, vt.tiktok.com)
        if lowered.contains("tiktok.com") {
            return .tiktok
        }

        // Pinterest (pinterest.com, pin.it)
        if lowered.contains("pinterest.com") || lowered.contains("pin.it") {
            return .pinterest
        }

        // Twitter / X (twitter.com, x.com, t.co)
        if lowered.contains("twitter.com") || lowered.contains("x.com") || lowered.contains("t.co/") {
            return .twitter
        }

        // Facebook (facebook.com, fb.watch, fb.com)
        if lowered.contains("facebook.com") || lowered.contains("fb.watch") || lowered.contains("fb.com") {
            return .facebook
        }

        // Reddit (reddit.com, redd.it)
        if lowered.contains("reddit.com") || lowered.contains("redd.it") {
            return .reddit
        }

        return .safari
    }

    /// Extract the first URL from a block of shared text.
    /// Instagram often shares URLs embedded in descriptive text.
    static func extractURLs(from text: String) -> [String] {
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        return matches.compactMap { match -> String? in
            guard let urlRange = Range(match.range, in: text) else { return nil }
            let urlString = String(text[urlRange])
            // Only keep http(s) URLs
            guard urlString.lowercased().hasPrefix("http") else { return nil }
            return urlString
        }
    }

    /// Determine the ingest source identifier for the backend API.
    /// Maps to the /ingest/{source} endpoint path component.
    static func ingestSource(for platform: DetectedPlatform) -> String {
        switch platform {
        case .youtube: return "youtube"
        case .instagram: return "instagram_reel"
        case .tiktok: return "tiktok"
        case .pinterest: return "pinterest"
        default: return "url"
        }
    }
}
