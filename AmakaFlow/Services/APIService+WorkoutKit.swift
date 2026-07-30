//
//  APIService+WorkoutKit.swift
//  AmakaFlow
//
//  AMA-2351 — BFF proxy to mapper POST /map/to-workoutkit.
//

import Foundation

extension APIService {
    /// POST `/v1/map/to-workoutkit` — mapper SportRouter + CustomComposer DTO.
    ///
    /// Returns raw JSON so the caller can decode `WKPlanDTO` via WorkoutKitSync
    /// and read composition metadata without requiring a sync package bump.
    func mapToWorkoutKit(
        blocksJSON: [String: Any],
        deliveryPrefs: [String: Any]? = nil
    ) async throws -> Data {
        var body: [String: Any] = ["blocks_json": blocksJSON]
        if let deliveryPrefs {
            body["delivery_prefs"] = deliveryPrefs
        }
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/map/to-workoutkit",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return try await requestData(request, successStatusCodes: 200...200)
    }
}
