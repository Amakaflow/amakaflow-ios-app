//
//  BuilderV3ExerciseSearchClient.swift
//  AmakaFlow
//
//  AMA-2372 — thin client for `GET /v1/exercises/search?q=&limit=`.
//  Matches mobile-bff camelCase ExerciseSearchResponse. UITEST / network /
//  decode failures fall back to the local demo catalog so the picker never
//  surfaces an error sheet.
//

import Foundation

struct BuilderV3ExerciseSearchClient {
    /// Wire shape from mobile-bff `ExerciseSearchResponse` (AMA-2372).
    private struct SearchResponse: Decodable {
        struct Row: Decodable {
            var id: String?
            var name: String
            var primaryMuscles: [String]?
            var secondaryMuscles: [String]?
            var equipment: [String]?
            var category: String?
            var rank: Double?
        }

        var results: [Row]
        var count: Int?
        var query: String?
    }

    private let apiService: APIService
    private let useFixtures: Bool

    init(
        apiService: APIService = .shared,
        useFixtures: Bool = UITestEnvironment.shared.useFixtures
    ) {
        self.apiService = apiService
        self.useFixtures = useFixtures
    }

    /// Never throws — callers always get a usable (possibly fixture) result set.
    func search(query: String, limit: Int = 30) async -> [BuilderV3ExerciseItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Self.fixtureResults(matching: "")
        }
        guard !useFixtures else {
            return Self.fixtureResults(matching: trimmed)
        }
        do {
            let request = try await apiService.makeAPIRequest(
                path: "/v1/exercises/search",
                queryItems: [
                    URLQueryItem(name: "q", value: trimmed),
                    URLQueryItem(name: "limit", value: String(limit))
                ],
                method: "GET"
            )
            // BFF already emits camelCase; use generated decoder (no snake_case).
            let response = try await apiService.request(
                request,
                decode: SearchResponse.self,
                decoder: APIService.makeGeneratedDecoder()
            )
            guard !response.results.isEmpty else {
                return Self.fixtureResults(matching: trimmed)
            }
            return response.results.map { Self.mapRow($0) }
        } catch {
            return Self.fixtureResults(matching: trimmed)
        }
    }

    static func fixtureResults(matching query: String) -> [BuilderV3ExerciseItem] {
        BuilderV3ExerciseLibrary.demo.filter { BuilderV3ExerciseLibrary.matches($0, query: query) }
    }

    private static func mapRow(_ row: SearchResponse.Row) -> BuilderV3ExerciseItem {
        let muscle = row.primaryMuscles?.first
            ?? row.secondaryMuscles?.first
            ?? row.category
            ?? ""
        let equipmentKey = row.equipment?.first
        let equipmentLabel = equipmentKey.map(BuilderV3ExerciseLibrary.equipmentFilterLabel)
            ?? "Bodyweight"
        return BuilderV3ExerciseItem(
            name: row.name,
            muscle: muscle,
            equipmentKey: equipmentKey,
            equipmentLabel: equipmentLabel
        )
    }
}
