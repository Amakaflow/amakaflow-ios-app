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

/// Why a fetch fell back to fixtures.
///
/// AMA-2449: for a year the picker served fixtures on every call because the
/// requests went to the wrong host, and a permanent 404 was indistinguishable
/// from a dropped connection — both produced the same small `MOCK` badge. A
/// missing route is a wiring mistake, not a network condition, so it is
/// classified separately and trapped in debug.
enum BuilderV3ExerciseFallbackReason: Equatable, Sendable {
    /// Deliberate: UI tests asked for fixtures.
    case fixturesRequested
    /// The query was empty, so there was nothing to ask the server.
    case noQuery
    /// The upstream route does not exist. A bug in this app, not a bad network.
    case routeMissing
    /// Anything genuinely transient — offline, timeout, 5xx, bad payload.
    case requestFailed
}

struct BuilderV3ExerciseFetchResult: Equatable, Sendable {
    var items: [BuilderV3ExerciseItem]
    /// Server rows before ID filtering — pagination must advance by this count.
    var receivedRowCount: Int
    var mode: BuilderV3ExerciseFetchMode
    /// Set only when `mode == .mock`.
    var fallbackReason: BuilderV3ExerciseFallbackReason?

    init(
        items: [BuilderV3ExerciseItem],
        receivedRowCount: Int? = nil,
        mode: BuilderV3ExerciseFetchMode,
        fallbackReason: BuilderV3ExerciseFallbackReason? = nil
    ) {
        self.items = items
        self.receivedRowCount = receivedRowCount ?? items.count
        self.mode = mode
        self.fallbackReason = fallbackReason
    }

    /// Fixtures because of a failure, classified. Traps in debug when the cause
    /// is a missing route, so a host or path mistake fails loudly in tests and
    /// dev builds instead of quietly serving demo data.
    static func fallback(
        items: [BuilderV3ExerciseItem],
        error: Error,
        endpoint: String
    ) -> BuilderV3ExerciseFetchResult {
        let reason = classify(error)
        if reason == .routeMissing {
            assertionFailure(
                "\(endpoint) returned 404 — wrong host or path. "
                    + "Exercise routes live on mobile-bff (APIService.bffURL), not mapper-api."
            )
        }
        return BuilderV3ExerciseFetchResult(items: items, mode: .mock, fallbackReason: reason)
    }

    /// Split from `fallback` so the rule can be asserted directly — `fallback`
    /// traps on `.routeMissing` by design, which a test cannot exercise.
    static func classify(_ error: Error) -> BuilderV3ExerciseFallbackReason {
        APIError.coerce(error).category == .notFound ? .routeMissing : .requestFailed
    }
}

struct BuilderV3ExerciseSearchClient {
    /// Paths are relative to `APIService.bffURL`, which already carries the
    /// `/v1` prefix. These routes are served by mobile-bff; the default
    /// `makeAPIRequest` base is mapper-api, which 404s on both (AMA-2449).
    static let searchPath = "/exercises/search"
    static let listPath = "/exercises"

    private let apiService: APIService
    private let useFixtures: Bool

    init(
        apiService: APIService = .shared,
        useFixtures: Bool? = nil
    ) {
        self.apiService = apiService
        #if DEBUG
        self.useFixtures = useFixtures ?? (LaunchConfig.active?.useFixtures == true)
        #else
        self.useFixtures = useFixtures ?? false
        #endif
    }

    /// Request builders are split out so a test can assert the URL these
    /// routes actually resolve to. Passing `headers` skips the auth round trip;
    /// production leaves it nil and gets the real headers (AMA-2449).
    func makeSearchRequest(
        query: String,
        limit: Int,
        headers: [String: String]? = nil
    ) async throws -> URLRequest {
        try await apiService.makeAPIRequest(
            baseURL: apiService.bffURL,
            path: Self.searchPath,
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit))
            ],
            method: "GET",
            headers: headers
        )
    }

    func makeListRequest(
        queryItems: [URLQueryItem],
        headers: [String: String]? = nil
    ) async throws -> URLRequest {
        try await apiService.makeAPIRequest(
            baseURL: apiService.bffURL,
            path: Self.listPath,
            queryItems: queryItems,
            method: "GET",
            headers: headers
        )
    }

    /// Never throws. Failures are explicit through `.mock`; live empty stays empty.
    func search(query: String, limit: Int = 30) async -> BuilderV3ExerciseFetchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return BuilderV3ExerciseFetchResult(
                items: Self.fixtureResults(matching: ""),
                mode: .mock,
                fallbackReason: .noQuery
            )
        }
        guard !useFixtures else {
            return BuilderV3ExerciseFetchResult(
                items: Self.fixtureResults(matching: trimmed),
                mode: .mock,
                fallbackReason: .fixturesRequested
            )
        }
        do {
            let request = try await makeSearchRequest(query: trimmed, limit: limit)
            // BFF already emits camelCase; use generated decoder (no snake_case).
            let response = try await apiService.request(
                request,
                decode: BuilderV3ExerciseSearchResponse.self,
                decoder: APIService.makeGeneratedDecoder()
            )
            let rows = response.results
            return BuilderV3ExerciseFetchResult(
                items: rows.compactMap { Self.mapRow($0) },
                receivedRowCount: rows.count,
                mode: .live
            )
        } catch {
            return .fallback(
                items: Self.fixtureResults(matching: trimmed),
                error: error,
                endpoint: Self.searchPath
            )
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
            return BuilderV3ExerciseFetchResult(
                items: fixture,
                mode: .mock,
                fallbackReason: .fixturesRequested
            )
        }

        do {
            // Strength → Core chip is `abs`, but many trunk moves are tagged
            // `obliques` only (Cable Ab Twist). Merge both on the first page.
            if muscle == "abs", offset == 0 {
                async let absPage = listLivePage(
                    category: category,
                    muscle: "abs",
                    equipment: equipment,
                    limit: limit,
                    offset: 0
                )
                async let obliquePage = listLivePage(
                    category: category,
                    muscle: "obliques",
                    equipment: equipment,
                    limit: limit,
                    offset: 0
                )
                let (absPageResult, obliquePageResult) = try await (absPage, obliquePage)
                var seen = Set<String>()
                var merged: [BuilderV3ExerciseItem] = []
                for item in absPageResult.items + obliquePageResult.items {
                    guard seen.insert(item.id).inserted else { continue }
                    merged.append(item)
                }
                return BuilderV3ExerciseFetchResult(
                    items: merged,
                    // Pagination advances on the primary muscle page only.
                    receivedRowCount: absPageResult.receivedRowCount,
                    mode: .live
                )
            }

            let page = try await listLivePage(
                category: category,
                muscle: muscle,
                equipment: equipment,
                limit: limit,
                offset: offset
            )
            return BuilderV3ExerciseFetchResult(
                items: page.items,
                receivedRowCount: page.receivedRowCount,
                mode: .live
            )
        } catch {
            return .fallback(items: fixture, error: error, endpoint: Self.listPath)
        }
    }

    private func listLivePage(
        category: String,
        muscle: String?,
        equipment: String?,
        limit: Int,
        offset: Int
    ) async throws -> BuilderV3ExerciseFetchResult {
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
        let request = try await makeListRequest(queryItems: queryItems)
        let response = try await apiService.request(
            request,
            decode: BuilderV3ExerciseListResponse.self,
            decoder: APIService.makeGeneratedDecoder()
        )
        let rows = response.exercises
        return BuilderV3ExerciseFetchResult(
            items: rows.compactMap { Self.mapRow($0) },
            receivedRowCount: rows.count,
            mode: .live
        )
    }

    static func fixtureResults(matching query: String) -> [BuilderV3ExerciseItem] {
        BuilderV3ExerciseLibrary.demo.filter { BuilderV3ExerciseLibrary.matches($0, query: query) }
    }

    /// Rows without a stable catalog `id` are dropped — UUID fallbacks break pagination dedupe.
    private static func mapRow(_ row: BuilderV3ExerciseSearchRow) -> BuilderV3ExerciseItem? {
        guard let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        let muscle = row.primaryMuscles?.first
            ?? row.secondaryMuscles?.first
            ?? row.category
            ?? ""
        let equipmentKey = row.equipment?.first
        let equipmentLabel = equipmentKey.map(BuilderV3ExerciseLibrary.equipmentFilterLabel)
            ?? "Bodyweight"
        return BuilderV3ExerciseItem(
            id: id,
            name: row.name,
            muscle: muscle,
            equipmentKey: equipmentKey,
            equipmentLabel: equipmentLabel
        )
    }
}
