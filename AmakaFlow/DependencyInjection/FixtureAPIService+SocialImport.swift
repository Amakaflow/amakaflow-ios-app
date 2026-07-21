//
//  FixtureAPIService+SocialImport.swift
//  AmakaFlow
//
//  AMA-2285: social import fixtures (no scraping).
//

#if DEBUG
import Foundation

extension FixtureAPIService {
    func ingestSocialURL(url: String, platform: SocialImportPlatform) async throws -> Data {
        print("[FixtureAPIService] Stub: ingestSocialURL(\(platform.rawValue))")
        let payload: [String: Any] = [
            "title": "DB Full-body AMRAP",
            "sport": "cardio",
            "description": "Four main rounds of full-body conditioning plus a sled finisher. Parsed from the reel; nothing saved yet.",
            "source_url": url,
            "creator": "gospelofgainz",
            "blocks": [
                [
                    "label": "Round 1–3",
                    "rounds": 3,
                    "exercises": [
                        [
                            "name": "Wall balls",
                            "reps": 20,
                            "load": "med ball 6 kg",
                            "focus": "Quads · Shoulders"
                        ],
                        [
                            "name": "Barbell thrusters",
                            "reps": 12,
                            "weight": 40,
                            "weight_unit": "kg",
                            "focus": "Full body"
                        ],
                        [
                            "name": "Burpee broad jumps",
                            "reps": 10,
                            "load": "bodyweight",
                            "focus": "Full body"
                        ]
                    ]
                ],
                [
                    "label": "Finisher",
                    "rounds": 1,
                    "exercises": [
                        [
                            "name": "Sled push",
                            "sets": 2,
                            "distance_m": 20,
                            "weight": 80,
                            "weight_unit": "kg",
                            "focus": "Legs · Core"
                        ]
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    func ingestSocialText(text: String, source: String?) async throws -> Data {
        print("[FixtureAPIService] Stub: ingestSocialText")
        let payload: [String: Any] = [
            "title": "Fixture Text Import",
            "sport": "strength",
            "source": source as Any,
            "blocks": [
                ["exercises": [
                    ["name": "Fixture Press", "sets": 3, "reps": 8]
                ]]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    func ingestSocialImage(imageData: Data, filename: String) async throws -> Data {
        print("[FixtureAPIService] Stub: ingestSocialImage(\(filename))")
        let payload: [String: Any] = [
            "title": "Fixture Screenshot Import",
            "sport": "strength",
            "blocks": [
                ["exercises": [
                    ["name": "Fixture Row", "sets": 3, "reps": 12]
                ]]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    func socialImportEquipmentContext() async -> (empty: Bool, note: String?) {
        (true, "Fixture: no equipment profile — continuing.")
    }

    func suggestStructure(text: String, source: String?) async throws -> StructureSuggestResult {
        print("[FixtureAPIService] Stub: suggestStructure")
        return StructureClarifyFixtures.dmqSuggestResult
    }

    func applyStructure(_ request: ApplyStructureRequest) async throws -> ApplyStructureResult {
        print("[FixtureAPIService] Stub: applyStructure note=\(request.note ?? "nil")")
        if let note = request.note?.lowercased(), note.contains("leave it flat") {
            let flat = request.blocks.flatMap { block in
                block.exercises.map {
                    StructureBlockModel(type: .sets, exercises: [$0], structureSource: .userConfirmed)
                }
            }
            return ApplyStructureResult(blocks: flat)
        }
        return ApplyStructureResult(blocks: StructureClarifyFixtures.dmqNoteAppliedBlocks)
    }
}
#endif
