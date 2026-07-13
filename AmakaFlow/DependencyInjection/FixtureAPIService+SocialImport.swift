//
//  FixtureAPIService+SocialImport.swift
//  AmakaFlow
//
//  AMA-2285: social import fixtures (no scraping).
//

import Foundation

extension FixtureAPIService {
    func ingestSocialURL(url: String, platform: SocialImportPlatform) async throws -> Data {
        print("[FixtureAPIService] Stub: ingestSocialURL(\(platform.rawValue))")
        let payload: [String: Any] = [
            "title": "Fixture Social Import",
            "sport": "strength",
            "source_url": url,
            "blocks": [
                ["exercises": [
                    ["name": "Fixture Squat", "sets": 3, "reps": 10]
                ]]
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
}
