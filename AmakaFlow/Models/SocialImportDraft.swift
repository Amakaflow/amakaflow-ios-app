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

    /// AMA-2297: normalize IG `/reels/{id}` → `/reel/{id}` before ingest.
    static func normalizeForIngest(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard detect(from: trimmed) == .instagram else { return trimmed }
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)(instagram\\.com/)reels(/)",
            options: []
        ) else { return trimmed }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.stringByReplacingMatches(
            in: trimmed,
            options: [],
            range: range,
            withTemplate: "$1reel$2"
        )
    }
}

/// Trust/debug metadata pulled from the original social post (AMA-2297).
struct SocialImportPostProvenance: Equatable {
    var creator: String?
    var captionSnippet: String?
    var transcriptSnippet: String?
    var mode: String?
    var shortcode: String?

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

    var hasDisplayableInfo: Bool {
        creator != nil || contentSnippet != nil || shortcode != nil || mode != nil
    }
}

/// One editable exercise row in a social-import draft.
struct SocialImportExercise: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var sets: Int?
    var reps: Int?
    var seconds: Int?
    var notes: String?
}

/// Editable workout draft produced by ingest before Library save.
struct SocialImportDraft: Equatable {
    var title: String
    var sport: String
    var platform: SocialImportPlatform
    var sourceURL: String?
    var exercises: [SocialImportExercise]
    var equipmentNote: String?
    /// True when coaching equipment profile is empty — honest empty, continue.
    var equipmentEmpty: Bool
    /// AMA-2297: what we pulled from the original post (creator / caption / URL).
    var postProvenance: SocialImportPostProvenance? = nil

    var provenanceLabel: String { platform.displayName }

    func toWorkoutSaveIntervals() -> [WorkoutSaveInterval] {
        exercises.map { exercise in
            if let seconds = exercise.seconds, seconds > 0, exercise.reps == nil {
                return WorkoutSaveInterval(
                    type: "time",
                    name: exercise.name,
                    seconds: seconds,
                    target: exercise.notes
                )
            }
            return WorkoutSaveInterval(
                type: "reps",
                name: exercise.name,
                sets: exercise.sets ?? 3,
                reps: exercise.reps ?? 10,
                restSeconds: 60,
                load: exercise.notes
            )
        }
    }

    func toWorkoutSaveRequest() -> WorkoutSaveRequest {
        WorkoutSaveRequest(
            name: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sport: sport,
            intervals: toWorkoutSaveIntervals(),
            source: platform.workoutSourceRawValue,
            sourceUrl: sourceURL
        )
    }

    func toPreviewWorkout() -> Workout {
        let intervals: [WorkoutInterval] = exercises.map { exercise in
            if let seconds = exercise.seconds, seconds > 0, exercise.reps == nil {
                return .time(seconds: seconds, target: exercise.name)
            }
            return .reps(
                sets: exercise.sets ?? 3,
                reps: exercise.reps ?? 10,
                name: exercise.name,
                load: exercise.notes,
                restSec: 60,
                followAlongUrl: nil
            )
        }
        let source = WorkoutSource(rawValue: platform.workoutSourceRawValue) ?? .other
        return Workout(
            id: "draft-\(UUID().uuidString)",
            name: title,
            sport: WorkoutSport(rawValue: sport) ?? .strength,
            duration: max(intervals.count * 180, 600),
            intervals: intervals,
            source: source,
            sourceUrl: sourceURL
        )
    }

    /// Lenient decode of ingestor JSON (title/name/blocks or thin title/source).
    static func fromIngestJSON(
        _ data: Data,
        platform: SocialImportPlatform,
        sourceURL: String?,
        equipmentEmpty: Bool,
        equipmentNote: String?
    ) throws -> SocialImportDraft {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let title = (object["title"] as? String)
            ?? (object["name"] as? String)
            ?? "Imported Workout"

        let sport = (object["sport"] as? String)
            ?? (object["workout_type"] as? String)
            ?? (object["workoutType"] as? String)
            ?? "strength"

        var exercises: [SocialImportExercise] = []

        if let blocks = object["blocks"] as? [[String: Any]] {
            for block in blocks {
                let blockExercises = (block["exercises"] as? [[String: Any]]) ?? []
                for item in blockExercises {
                    let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let name, !name.isEmpty else { continue }
                    exercises.append(
                        SocialImportExercise(
                            name: name,
                            sets: item["sets"] as? Int,
                            reps: item["reps"] as? Int,
                            seconds: item["duration_sec"] as? Int ?? item["seconds"] as? Int,
                            notes: item["notes"] as? String
                        )
                    )
                }
            }
        }

        if exercises.isEmpty, let intervals = object["intervals"] as? [[String: Any]] {
            for item in intervals {
                let name = (item["name"] as? String) ?? (item["target"] as? String) ?? "Exercise"
                exercises.append(
                    SocialImportExercise(
                        name: name,
                        sets: item["sets"] as? Int,
                        reps: item["reps"] as? Int,
                        seconds: item["seconds"] as? Int,
                        notes: item["load"] as? String
                    )
                )
            }
        }

        // Thin success payload (title only) — still editable; AI never gatekeeps Edit.
        if exercises.isEmpty {
            exercises = [SocialImportExercise(name: "Add exercises", sets: 3, reps: 10)]
        }

        let resolvedURL = sourceURL
            ?? (object["source_url"] as? String)
            ?? (object["sourceUrl"] as? String)
            ?? (object["source"] as? String).flatMap { $0.hasPrefix("http") ? $0 : nil }

        let postProvenance = Self.postProvenance(from: object)

        return SocialImportDraft(
            title: title,
            sport: sport.lowercased(),
            platform: platform,
            sourceURL: resolvedURL,
            exercises: exercises,
            equipmentNote: equipmentNote,
            equipmentEmpty: equipmentEmpty,
            postProvenance: postProvenance
        )
    }

    private static func postProvenance(from object: [String: Any]) -> SocialImportPostProvenance? {
        let provenance = object["_provenance"] as? [String: Any]
        let creator = (provenance?["creator"] as? String)
            ?? (object["creator"] as? String)
            ?? (object["author"] as? String)
        let captionSnippet = (provenance?["caption_snippet"] as? String)
            ?? (provenance?["caption"] as? String)
            ?? (object["caption"] as? String)
        let transcriptSnippet = (provenance?["transcript_snippet"] as? String)
            ?? (provenance?["transcript"] as? String)
        let mode = provenance?["mode"] as? String
        let shortcode = provenance?["shortcode"] as? String

        let result = SocialImportPostProvenance(
            creator: creator,
            captionSnippet: captionSnippet,
            transcriptSnippet: transcriptSnippet,
            mode: mode,
            shortcode: shortcode
        )
        return result.hasDisplayableInfo ? result : nil
    }
}
