//
//  BuilderV3ExerciseSearchClient.swift
//  AmakaFlow
//
//  AMA-2372 / AMA-2384 — thin client for exercise search and category browse.
//  Network/decode failures use a visible MOCK fixture; successful empty
//  responses remain honestly empty.
//

import Foundation

/// Wire row from mobile-bff `ExerciseSearchResult` (AMA-2372).
private struct BuilderV3ExerciseSearchRow: Decodable {
    var id: String?
    var name: String
    var primaryMuscles: [String]?
    var secondaryMuscles: [String]?
    var equipment: [String]?
    var category: String?
    var rank: Double?
}

/// Wire payload from mobile-bff `ExerciseSearchResponse` (AMA-2372).
private struct BuilderV3ExerciseSearchResponse: Decodable {
    var results: [BuilderV3ExerciseSearchRow]
    var count: Int?
    var query: String?
}

private struct BuilderV3ExerciseListResponse: Decodable {
    var exercises: [BuilderV3ExerciseSearchRow]
    var count: Int?
}

enum BuilderV3ExerciseFetchMode: Equatable, Sendable {
    case live
    case mock
}

struct BuilderV3ExerciseFetchResult: Equatable, Sendable {
    var items: [BuilderV3ExerciseItem]
    var mode: BuilderV3ExerciseFetchMode
}

struct BuilderV3ExerciseSearchClient {
    private let apiService: APIService
    private let useFixtures: Bool

    init(
        apiService: APIService = .shared,
        useFixtures: Bool = UITestEnvironment.shared.useFixtures
    ) {
        self.apiService = apiService
        self.useFixtures = useFixtures
    }

    /// Never throws. Failures are explicit through `.mock`; live empty stays empty.
    func search(query: String, limit: Int = 30) async -> BuilderV3ExerciseFetchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return BuilderV3ExerciseFetchResult(items: Self.fixtureResults(matching: ""), mode: .mock)
        }
        guard !useFixtures else {
            return BuilderV3ExerciseFetchResult(items: Self.fixtureResults(matching: trimmed), mode: .mock)
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
                decode: BuilderV3ExerciseSearchResponse.self,
                decoder: APIService.makeGeneratedDecoder()
            )
            return BuilderV3ExerciseFetchResult(
                items: response.results.map { Self.mapRow($0) },
                mode: .live
            )
        } catch {
            return BuilderV3ExerciseFetchResult(items: Self.fixtureResults(matching: trimmed), mode: .mock)
        }
    }

    /// Lists one server category with an optional category-specific chip filter.
    func list(
        category: String,
        muscle: String?,
        equipment: String?,
        limit: Int = 40,
        offset: Int = 0
    ) async -> BuilderV3ExerciseFetchResult {
        let fixture = BuilderV3ExerciseLibrary.fixtureItems(
            category: category,
            muscle: muscle,
            equipment: equipment
        )
        guard !useFixtures else {
            return BuilderV3ExerciseFetchResult(items: fixture, mode: .mock)
        }

        var queryItems = [
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let muscle {
            queryItems.append(URLQueryItem(name: "muscle", value: muscle))
        }
        if let equipment {
            queryItems.append(URLQueryItem(name: "equipment", value: equipment))
        }

        do {
            let request = try await apiService.makeAPIRequest(
                path: "/v1/exercises",
                queryItems: queryItems,
                method: "GET"
            )
            let response = try await apiService.request(
                request,
                decode: BuilderV3ExerciseListResponse.self,
                decoder: APIService.makeGeneratedDecoder()
            )
            return BuilderV3ExerciseFetchResult(
                items: response.exercises.map { Self.mapRow($0) },
                mode: .live
            )
        } catch {
            return BuilderV3ExerciseFetchResult(items: fixture, mode: .mock)
        }
    }

    static func fixtureResults(matching query: String) -> [BuilderV3ExerciseItem] {
        BuilderV3ExerciseLibrary.demo.filter { BuilderV3ExerciseLibrary.matches($0, query: query) }
    }

    private static func mapRow(_ row: BuilderV3ExerciseSearchRow) -> BuilderV3ExerciseItem {
        let muscle = row.primaryMuscles?.first
            ?? row.secondaryMuscles?.first
            ?? row.category
            ?? ""
        let equipmentKey = row.equipment?.first
        let equipmentLabel = equipmentKey.map(BuilderV3ExerciseLibrary.equipmentFilterLabel)
            ?? "Bodyweight"
        return BuilderV3ExerciseItem(
            id: row.id ?? UUID().uuidString,
            name: row.name,
            muscle: muscle,
            equipmentKey: equipmentKey,
            equipmentLabel: equipmentLabel
        )
    }
}
