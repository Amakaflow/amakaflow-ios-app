//
//  APIService+WorkoutTypes.swift
//  AmakaFlow
//
//  Canonical workout taxonomy endpoints served by the mobile BFF.
//

import Foundation

private struct WorkoutTypeMatchRequest: Encodable {
    let title: String
}

extension APIService {
    func fetchWorkoutTypes(aiPresetOnly: Bool = false) async throws -> [WorkoutTypeItem] {
        let queryItems = aiPresetOnly
            ? [URLQueryItem(name: "ai_preset", value: "true")]
            : []
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/workout-types",
            queryItems: queryItems,
            method: "GET"
        )
        return try await self.request(
            request,
            decode: [WorkoutTypeItem].self,
            successStatusCodes: 200...200
        )
    }

    func matchWorkoutType(title: String) async throws -> WorkoutTypeMatchResponse {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/workout-types/match",
            method: "POST",
            body: try encodeJSONBody(WorkoutTypeMatchRequest(title: title))
        )
        return try await self.request(
            request,
            decode: WorkoutTypeMatchResponse.self,
            successStatusCodes: 200...200
        )
    }
}
