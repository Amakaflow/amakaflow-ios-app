//
//  SocialImportDraft.swift
//  AmakaFlow
//
//  AMA-2285: structured draft from social ingest (share / paste / screenshot).
//  Ingestor returns workout JSON (title/blocks/exercises) — this maps it into
//  an editable library draft with provenance. No scraping on-device.
//

import Foundation

/// Platform provenance for social → library imports (AMA-2285).
enum SocialImportPlatform: String, Codable, CaseIterable, Equatable {
    case instagram
    case tiktok
    case youtube
    case manual
    case coach
    // swiftlint:disable:next identifier_name
    case ai
    case image
    case web

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .manual: return "Manual"
        case .coach: return "Coach"
        case .ai: return "AI"
        case .image: return "Screenshot"
        case .web: return "Web Link"
        }
    }

    /// Mapper-api / library `source` value for persistence + badge.
    var workoutSourceRawValue: String {
        switch self {
        case .instagram: return WorkoutSource.instagram.rawValue
        case .tiktok: return WorkoutSource.tiktok.rawValue
        case .youtube: return WorkoutSource.youtube.rawValue
        case .manual: return WorkoutSource.manual.rawValue
        case .coach: return WorkoutSource.coach.rawValue
        case .ai: return WorkoutSource.ai.rawValue
        case .image: return WorkoutSource.image.rawValue
        case .web: return WorkoutSource.other.rawValue
        }
    }

    /// Ingestor path component under `/ingest/{source}`.
    var ingestPath: String {
        switch self {
        case .instagram: return "instagram_reel"
        case .tiktok: return "tiktok"
        case .youtube: return "youtube"
        case .manual, .ai, .coach: return "text"
        case .image: return "image"
        case .web: return "url"
        }
    }

    static func detect(from urlString: String) -> SocialImportPlatform {
        if let host = Self.host(from: urlString) {
            if Self.hostMatches(host, roots: ["youtube.com", "youtu.be"]) { return .youtube }
            if Self.hostMatches(host, roots: ["instagram.com", "instagr.am"]) { return .instagram }
            if Self.hostMatches(host, roots: ["tiktok.com"]) { return .tiktok }
            return .web
        }

        // Fallback for bare host-like strings without a scheme.
        let lowered = urlString.lowercased()
        if lowered.contains("youtube.com") || lowered.contains("youtu.be") { return .youtube }
        if lowered.contains("instagram.com") || lowered.contains("instagr.am") { return .instagram }
        if lowered.contains("tiktok.com") { return .tiktok }
        return .web
    }

    /// True when Library paste should open workout import (not knowledge bookmark).
    static func isWorkoutImportURL(_ urlString: String) -> Bool {
        switch detect(from: urlString) {
        case .instagram, .tiktok, .youtube: return true
        default: return false
        }
    }

    /// AMA-2297: normalize IG `/reels/{id}` → `/reel/{id}` and drop share tracking params (`igsh`, etc.) before ingest.
    static func normalizeForIngest(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard detect(from: trimmed) == .instagram else { return trimmed }

        var normalized = trimmed
        if let regex = try? NSRegularExpression(
            pattern: "(?i)((?:instagram\\.com|instagr\\.am)/)reels(/)",
            options: []
        ) {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                options: [],
                range: range,
                withTemplate: "$1reel$2"
            )
        }

        normalized = stripURLQueryAndFragment(normalized)
        return normalized
    }

    /// Canonical ingest URL — path only, no `igsh` / UTM query noise from share sheets.
    private static func stripURLQueryAndFragment(_ urlString: String) -> String {
        let withScheme = urlString.contains("://") ? urlString : "https://\(urlString)"
        guard var components = URLComponents(string: withScheme) else { return urlString }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? urlString
    }

    /// Parse host structurally so `instagram.com.evil` / `notinstagram.com` are rejected.
    private static func host(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host.lowercased()
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)?.host?.lowercased()
    }

    private static func hostMatches(_ host: String, roots: [String]) -> Bool {
        roots.contains { root in
            host == root || host.hasSuffix(".\(root)")
        }
    }
}

/// Trust/debug metadata pulled from the original social post (AMA-2297 / AMA-2302).
struct SocialImportPostProvenance: Equatable {
    var creator: String?
    var captionSnippet: String?
    var transcriptSnippet: String?
    var mode: String?
    var shortcode: String?
    /// Backend ladder: how the workout was extracted (`_provenance.extraction_method`).
    var extractionMethod: String?
    /// Whether the ≥2-exercise gate passed (`_provenance.exercise_gate_passed`).
    var exerciseGatePassed: Bool?
    /// Which ladder tier ran (`_provenance.tier_attempted`).
    var tierAttempted: String?

    var creatorDisplay: String {
        guard let creator = creator?.trimmingCharacters(in: .whitespacesAndNewlines),
              !creator.isEmpty,
              creator.lowercased() != "unknown" else {
            return "creator unknown"
        }
        return creator.hasPrefix("@") ? creator : "@\(creator)"
    }

    /// 1–2 line snippet for verifying we fetched real post content.
    var contentSnippet: String? {
        let caption = captionSnippet?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let caption, !caption.isEmpty { return String(caption.prefix(180)) }
        let transcript = transcriptSnippet?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let transcript, !transcript.isEmpty { return String(transcript.prefix(180)) }
        return nil
    }

    /// Short badge label for trust strip (e.g. `apify_caption` → `Caption`).
    var extractionMethodDisplay: String? {
        guard let raw = extractionMethod?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "apify_caption": return "Caption"
        case "apify_transcript": return "Transcript"
        case "whisper_audio": return "Audio"
        case "vision_frames", "sidecar_vision": return "Vision"
        case "hybrid_asr_vision": return "Audio + vision"
        case "hybrid_transcript_vision": return "Transcript + vision"
        default:
            return raw
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    var hasDisplayableInfo: Bool {
        creator != nil
            || contentSnippet != nil
            || shortcode != nil
            || mode != nil
            || extractionMethod != nil
    }
}

/// One editable exercise row in a social-import draft.
struct SocialImportExercise: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var sets: Int?
    var reps: Int?
    /// Textual rep prescription when not a plain integer (e.g. "8-10").
    var repsRange: String?
    var seconds: Int?
    var distanceMeters: Int?
    /// Load / tempo / instruction line (e.g. "70 kg", "build to heavy").
    var load: String?
    /// Target muscles from post (e.g. "Quads · Glutes").
    var focus: String?
    /// Legacy / freeform notes when not mapped to load or focus.
    var notes: String?
}

struct SocialImportBlock: Equatable, Codable {
    var label: String?
    var rounds: Int
    var exercises: [SocialImportExercise]
    /// ADR-017 block type (`sets` / `superset` / `circuit` / …).
    var type: String?
    /// Programmed rest intent in seconds (no timed/button toggle).
    var restSec: Int?
    /// Provenance: explicit | inferred | user_confirmed | user_note | unknown.
    var structureSource: String?

    enum CodingKeys: String, CodingKey {
        case label, rounds, exercises, type
        case restSec
        case structureSource
    }

    init(
        label: String? = nil,
        rounds: Int,
        exercises: [SocialImportExercise],
        type: String? = nil,
        restSec: Int? = nil,
        structureSource: String? = nil
    ) {
        self.label = label
        self.rounds = rounds
        self.exercises = exercises
        self.type = type
        self.restSec = restSec
        self.structureSource = structureSource
    }
}

/// Editable workout draft produced by ingest before Library save.
struct SocialImportDraft: Equatable {
    var title: String
    var sport: String
    var platform: SocialImportPlatform
    var sourceURL: String?
    var exercises: [SocialImportExercise]
    /// Block structure from ingest (preserves "Main lifts" / "Accessories").
    var blocks: [SocialImportBlock]
    var equipmentNote: String?
    /// True when coaching equipment profile is empty — honest empty, continue.
    var equipmentEmpty: Bool
    /// AMA-2297: what we pulled from the original post (creator / caption / URL).
    var postProvenance: SocialImportPostProvenance?
    var workoutDescription: String?

    var provenanceLabel: String { platform.displayName }

    func toWorkoutSaveIntervals() -> [WorkoutSaveInterval] {
        exercises.map { exercise in
            let instruction = exercise.detailInstruction
            if let seconds = exercise.seconds, seconds > 0, exercise.reps == nil {
                return WorkoutSaveInterval(
                    type: "time",
                    name: exercise.name,
                    seconds: seconds,
                    target: instruction
                )
            }
            return WorkoutSaveInterval(
                type: "reps",
                name: exercise.name,
                sets: exercise.sets ?? 3,
                reps: exercise.reps ?? 10,
                restSeconds: 60,
                load: instruction
            )
        }
    }

    func toWorkoutSaveRequest() -> WorkoutSaveRequest {
        WorkoutSaveRequest(
            name: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sport: sport,
            intervals: toWorkoutSaveIntervals(),
            source: platform.workoutSourceRawValue,
            sourceUrl: sourceURL,
            description: workoutDescription,
            creatorName: postProvenance?.creator,
            blocks: blocksForPersistence()
        )
    }

    func toPreviewWorkout() -> Workout {
        let mappedBlocks: [Block] = blocksForPersistence().map { block in
            Block(
                label: block.label,
                structure: Self.previewStructure(for: block),
                rounds: max(1, block.rounds),
                exercises: block.exercises.map { $0.toExercise() }
            )
        }
        let resolvedBlocks = mappedBlocks.isEmpty
            ? [Block(label: "Main block", structure: .straight, rounds: 1, exercises: exercises.map { $0.toExercise() })]
            : mappedBlocks
        let source = WorkoutSource(rawValue: platform.workoutSourceRawValue) ?? .other
        let resolvedSport = WorkoutSport(rawValue: sport) ?? .strength
        return Workout(
            id: "draft-\(UUID().uuidString)",
            name: title,
            sport: resolvedSport,
            duration: max(exercises.count * 180, 600),
            blocks: resolvedBlocks,
            description: workoutDescription ?? postProvenance?.contentSnippet,
            source: source,
            sourceUrl: sourceURL,
            creatorName: postProvenance?.creator
        )
    }

    private static func previewStructure(for block: SocialImportBlock) -> BlockStructure {
        let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if label == "finisher" { return .circuit }
        if label == "amrap" || label.contains("amrap") { return .amrap }
        if block.rounds > 1 { return .circuit }
        return .straight
    }
}

extension SocialImportExercise {
    var detailInstruction: String? {
        if let load, !load.isEmpty { return load }
        if let notes, !notes.isEmpty, !SocialImportDraft.looksLikeMuscleFocus(notes) { return notes }
        return nil
    }

    func toExercise() -> Exercise {
        let resolved = Workout.resolveLegacyLoadAndInstruction(from: detailInstruction)
        return Exercise(
            name: name,
            canonicalName: nil,
            sets: sets,
            reps: repsRange ?? reps.map(String.init),
            durationSeconds: seconds,
            load: resolved.load,
            restSeconds: 60,
            distance: distanceMeters.map(Double.init),
            notes: resolved.instruction,
            focus: focus,
            supersetGroup: nil
        )
    }
}
