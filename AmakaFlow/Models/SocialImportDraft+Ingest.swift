//
//  SocialImportDraft+Ingest.swift
//  AmakaFlow
//
//  AMA-2285 / AMA-2305 — lenient ingest JSON → draft.
//

import Foundation

extension SocialImportDraft {
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
                let decoded = Self.decodeIngestBlock(block)
                guard !decoded.blocks.isEmpty else { continue }
                parsedBlocks.append(contentsOf: decoded.blocks)
                exercises.append(contentsOf: decoded.exercises)
            }
        }

        if exercises.isEmpty, let intervals = object["intervals"] as? [[String: Any]] {
            for item in intervals {
                if let parsed = Self.parseExerciseItem(item) {
                    exercises.append(parsed)
                }
            }
        }

        // AMA-2302: never invent placeholder exercises for thin ingest — recoverable parse.
        if exercises.isEmpty {
            let thinProvenance = Self.postProvenance(from: object)
            throw SocialImportFailure.parse(
                message: SocialImportFailure.thinContentUserMessage(provenance: thinProvenance)
            )
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

        var draft = SocialImportDraft(
            title: title,
            sport: sport.lowercased(),
            platform: platform,
            sourceURL: resolvedURL,
            exercises: exercises,
            blocks: parsedBlocks,
            equipmentNote: equipmentNote,
            equipmentEmpty: equipmentEmpty,
            postProvenance: postProvenance,
            workoutDescription: description,
            enrichmentTombstones: EnrichmentTombstone.parseFromWorkoutData(object)
        )
        PrescriptionDefaults.applyToDraft(&draft)
        return draft
    }

    /// AMA-2414: map one ingest block JSON → one or more draft blocks.
    /// Nested `supersets[]` with empty `exercises[]` expand to per-pair blocks.
    private static func decodeIngestBlock(
        _ block: [String: Any]
    ) -> (blocks: [SocialImportBlock], exercises: [SocialImportExercise]) {
        let blockExercises = (block["exercises"] as? [[String: Any]]) ?? []
        let mapped = blockExercises.compactMap { parseExerciseItem($0) }
        let nestedPairs = (block["supersets"] as? [[String: Any]]) ?? []
        let blockType = (block["structure"] as? String) ?? (block["type"] as? String)
        let structureSource = (block["structure_source"] as? String)
            ?? (block["structureSource"] as? String)
        let restSec = block["rest_between_rounds_sec"] as? Int
            ?? block["rest_sec"] as? Int
            ?? block["restSec"] as? Int
        let enrichmentKind = (block["enrichment_kind"] as? String)
            ?? (block["enrichmentKind"] as? String)
        let restOpen = (block["rest_open"] as? Bool) ?? (block["restOpen"] as? Bool)
        let fieldProvenance = parseFieldProvenance(from: block)
        let baseLabel = block["label"] as? String
        let rounds = block["rounds"] as? Int ?? 1

        if mapped.isEmpty, !nestedPairs.isEmpty {
            var outBlocks: [SocialImportBlock] = []
            var outExercises: [SocialImportExercise] = []
            for (index, pair) in nestedPairs.enumerated() {
                let pairExercises = (pair["exercises"] as? [[String: Any]]) ?? []
                let pairMapped = pairExercises.compactMap { parseExerciseItem($0) }
                guard !pairMapped.isEmpty else { continue }
                let label = nestedSupersetLabel(
                    baseLabel: baseLabel,
                    index: index,
                    pairCount: nestedPairs.count
                )
                outBlocks.append(
                    SocialImportBlock(
                        label: label,
                        rounds: rounds,
                        exercises: pairMapped,
                        type: blockType ?? "superset",
                        restSec: restSec,
                        structureSource: structureSource,
                        enrichmentKind: enrichmentKind,
                        restOpen: restOpen,
                        fieldProvenance: fieldProvenance
                    )
                )
                outExercises.append(contentsOf: pairMapped)
            }
            return (outBlocks, outExercises)
        }

        guard !mapped.isEmpty else { return ([], []) }
        let draftBlock = SocialImportBlock(
            label: baseLabel,
            rounds: rounds,
            exercises: mapped,
            type: blockType,
            restSec: restSec,
            structureSource: structureSource,
            enrichmentKind: enrichmentKind,
            restOpen: restOpen,
            fieldProvenance: fieldProvenance
        )
        return ([draftBlock], mapped)
    }

    private static func nestedSupersetLabel(
        baseLabel: String?,
        index: Int,
        pairCount: Int
    ) -> String? {
        if pairCount == 1 { return baseLabel }
        if let baseLabel, !baseLabel.isEmpty {
            if baseLabel.lowercased().hasPrefix("superset") {
                return "Superset \(index + 1)"
            }
            return "\(baseLabel) \(index + 1)"
        }
        return "Superset \(index + 1)"
    }

    private static func parseExerciseItem(_ item: [String: Any]) -> SocialImportExercise? {
        let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }

        let sets = item["sets"] as? Int
        let repsRaw = item["reps"]
        let repsString = repsRaw as? String
        let reps = repsRaw as? Int ?? repsString.flatMap(Int.init)
        let structuredRange = RepsRange.ingestDisplay(from: item["reps_range"])
        let repsRange = structuredRange
            ?? repsString.flatMap { Int($0) == nil ? $0 : nil }
        let seconds = item["duration_sec"] as? Int ?? item["duration_seconds"] as? Int ?? item["seconds"] as? Int
        let distanceMeters = item["distance_m"] as? Int ?? item["distanceMeters"] as? Int
        let calories = item["calories"] as? Int
        let goal = item["goal"] as? [String: Any]
        let openGoal = ((goal?["kind"] as? String)?.lowercased() == "open")
            || (item["open_goal"] as? Bool) == true
            || (item["openGoal"] as? Bool) == true
        let restSeconds = item["rest_sec"] as? Int ?? item["restSeconds"] as? Int

        let focus = parseFocus(from: item)
        let load = parseLoad(from: item)
        let instruction = (item["instruction"] as? String)
            ?? (item["detail"] as? String)
            ?? (item["tempo"] as? String)
        let notes = item["notes"] as? String

        return SocialImportExercise(
            name: name,
            sets: sets,
            reps: reps,
            repsRange: repsRange,
            seconds: seconds,
            distanceMeters: distanceMeters,
            calories: calories,
            openGoal: openGoal ? true : nil,
            restSeconds: restSeconds,
            load: load ?? instruction,
            focus: focus,
            notes: notes,
            fieldProvenance: parseFieldProvenance(from: item),
            exerciseId: (item["exercise_id"] as? String) ?? (item["exerciseId"] as? String),
            warmupSets: WarmupSetRow.parseList(item["warmup_sets"] ?? item["warmupSets"]),
            restOpen: (item["rest_open"] as? Bool) ?? (item["restOpen"] as? Bool),
            structureSource: (item["structure_source"] as? String)
                ?? (item["structureSource"] as? String)
        )
    }

    /// AMA-2311 / AMA-2336 — per-field provenance map (`rest_sec` / `rest_open` ownership).
    private static func parseFieldProvenance(from item: [String: Any]) -> [String: String]? {
        let raw = (item["field_provenance"] as? [String: Any])
            ?? (item["fieldProvenance"] as? [String: Any])
        guard let raw else { return nil }
        let mapped = raw.compactMapValues { $0 as? String }
        return mapped.isEmpty ? nil : mapped
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
            shortcode: shortcode,
            extractionMethod: provenance?["extraction_method"] as? String,
            exerciseGatePassed: provenance?["exercise_gate_passed"] as? Bool,
            tierAttempted: provenance?["tier_attempted"] as? String
        )
        return result.hasDisplayableInfo ? result : nil
    }
}
