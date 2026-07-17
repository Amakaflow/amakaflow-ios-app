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
            pattern: "(?i)(instagram\\.com/)reels(/)",
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

    /// Blocks sent to mapper — keep section labels but refresh exercise rows from the flat list.
    func blocksForPersistence() -> [SocialImportBlock] {
        guard !blocks.isEmpty else {
            return [SocialImportBlock(label: "Main block", rounds: 1, exercises: exercises)]
        }
        if blocks.count == 1 {
            let block = blocks[0]
            return [
                SocialImportBlock(
                    label: block.label ?? "Main block",
                    rounds: max(1, block.rounds),
                    exercises: exercises
                )
            ]
        }
        return reconciledMultiBlocks()
    }

    /// Reconcile multi-block rows with the flat editable list by exercise id.
    private func reconciledMultiBlocks() -> [SocialImportBlock] {
        let flatByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        var assignedIDs = Set<SocialImportExercise.ID>()
        var reconciled = blocks.map { block -> SocialImportBlock in
            let reconciledExercises = block.exercises.compactMap { flatByID[$0.id] }
            assignedIDs.formUnion(reconciledExercises.map(\.id))
            return SocialImportBlock(
                label: block.label,
                rounds: max(1, block.rounds),
                exercises: reconciledExercises
            )
        }
        let unassigned = exercises.filter { !assignedIDs.contains($0.id) }
        if !unassigned.isEmpty, let firstIndex = reconciled.indices.first {
            let block = reconciled[firstIndex]
            reconciled[firstIndex] = SocialImportBlock(
                label: block.label,
                rounds: block.rounds,
                exercises: block.exercises + unassigned
            )
        }
        return reconciled
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

    /// Lenient decode of ingestor JSON (title/name/blocks or thin title/source).
    static func fromIngestJSON(
        _ data: Data,
        platform: SocialImportPlatform,
        sourceURL: String?,
        equipmentEmpty: Bool,
        equipmentNote: String?
    ) throws -> SocialImportDraft {
        var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let nested = root["workout_data"] as? [String: Any] {
            root = nested.merging(root) { current, _ in current }
        }

        let object = root

        let title = (object["title"] as? String)
            ?? (object["name"] as? String)
            ?? "Imported Workout"

        let sport = (object["sport"] as? String)
            ?? (object["workout_type"] as? String)
            ?? (object["workoutType"] as? String)
            ?? "strength"

        var parsedBlocks: [SocialImportBlock] = []
        var exercises: [SocialImportExercise] = []

        if let blocks = object["blocks"] as? [[String: Any]] {
            for block in blocks {
                let blockExercises = (block["exercises"] as? [[String: Any]]) ?? []
                let mapped = blockExercises.compactMap { Self.parseExerciseItem($0) }
                guard !mapped.isEmpty else { continue }
                parsedBlocks.append(
                    SocialImportBlock(
                        label: block["label"] as? String,
                        rounds: block["rounds"] as? Int ?? 1,
                        exercises: mapped
                    )
                )
                exercises.append(contentsOf: mapped)
            }
        }

        if exercises.isEmpty, let intervals = object["intervals"] as? [[String: Any]] {
            for item in intervals {
                if let parsed = Self.parseExerciseItem(item) {
                    exercises.append(parsed)
                }
            }
        }

        // Thin success payload (title only) — still editable; AI never gatekeeps Edit.
        if exercises.isEmpty {
            exercises = [SocialImportExercise(name: "Add exercises", sets: 3, reps: 10)]
        }

        if parsedBlocks.isEmpty && !exercises.isEmpty {
            parsedBlocks = [SocialImportBlock(label: "Main block", rounds: 1, exercises: exercises)]
        }

        let resolvedURL = sourceURL
            ?? (object["source_url"] as? String)
            ?? (object["sourceUrl"] as? String)
            ?? (object["source"] as? String).flatMap { $0.hasPrefix("http") ? $0 : nil }

        let postProvenance = Self.postProvenance(from: object)
        let description = (object["description"] as? String)
            ?? (object["summary"] as? String)
            ?? postProvenance?.contentSnippet

        return SocialImportDraft(
            title: title,
            sport: sport.lowercased(),
            platform: platform,
            sourceURL: resolvedURL,
            exercises: exercises,
            blocks: parsedBlocks,
            equipmentNote: equipmentNote,
            equipmentEmpty: equipmentEmpty,
            postProvenance: postProvenance,
            workoutDescription: description
        )
    }

    private static func parseExerciseItem(_ item: [String: Any]) -> SocialImportExercise? {
        let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }

        let sets = item["sets"] as? Int ?? defaultSets(from: item)
        let repsRaw = item["reps"]
        let repsString = repsRaw as? String
        let reps = repsRaw as? Int ?? repsString.flatMap(Int.init)
        let repsRange = (item["reps_range"] as? String)
            ?? repsString.flatMap { Int($0) == nil ? $0 : nil }
        let seconds = item["duration_sec"] as? Int ?? item["duration_seconds"] as? Int ?? item["seconds"] as? Int
        let distanceMeters = item["distance_m"] as? Int ?? item["distanceMeters"] as? Int

        let focus = parseFocus(from: item)
        let load = parseLoad(from: item)
        let instruction = (item["instruction"] as? String)
            ?? (item["detail"] as? String)
            ?? (item["tempo"] as? String)
            ?? (item["reps_range"] as? String)
        let notes = item["notes"] as? String

        return SocialImportExercise(
            name: name,
            sets: sets,
            reps: reps,
            repsRange: repsRange,
            seconds: seconds,
            distanceMeters: distanceMeters,
            load: load ?? instruction,
            focus: focus,
            notes: notes
        )
    }

    private static func defaultSets(from item: [String: Any]) -> Int? {
        if item["reps"] != nil || item["duration_sec"] != nil { return 3 }
        return nil
    }

    private static func parseFocus(from item: [String: Any]) -> String? {
        if let focus = item["focus"] as? String, !focus.isEmpty { return focus }
        if let muscleGroup = item["muscle_group"] as? String, !muscleGroup.isEmpty { return muscleGroup }
        if let muscleGroup = item["muscleGroup"] as? String, !muscleGroup.isEmpty { return muscleGroup }
        if let groups = item["muscle_groups"] as? [String], !groups.isEmpty {
            return groups.joined(separator: " · ")
        }
        if let notes = item["notes"] as? String, Self.looksLikeMuscleFocus(notes) {
            return notes
        }
        return nil
    }

    private static func parseLoad(from item: [String: Any]) -> String? {
        if let load = item["load"] as? String, !load.isEmpty { return load }
        if let weight = item["weight"] {
            let unit = (item["weight_unit"] as? String) ?? (item["weightUnit"] as? String) ?? "kg"
            if let doubleWeight = weight as? Double {
                return formatWeight(doubleWeight, unit: unit)
            }
            if let intWeight = weight as? Int {
                return formatWeight(Double(intWeight), unit: unit)
            }
            if let stringWeight = weight as? String, !stringWeight.isEmpty {
                if Self.stringContainsLoadUnit(stringWeight) {
                    return stringWeight
                }
                return "\(stringWeight) \(unit)"
            }
        }
        return nil
    }

    private static func formatWeight(_ value: Double, unit: String) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value)) \(unit)"
        }
        return String(format: "%.1f", value) + " \(unit)"
    }

    private static func stringContainsLoadUnit(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["kg", "lb", "lbs", "%", "bw", "bodyweight"].contains { lowered.contains($0) }
    }

    static func looksLikeMuscleFocus(_ text: String) -> Bool {
        Exercise.looksLikeMuscleFocus(text)
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
