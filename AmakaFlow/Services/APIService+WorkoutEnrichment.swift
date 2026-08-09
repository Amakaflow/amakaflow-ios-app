//
//  APIService+WorkoutEnrichment.swift
//  AmakaFlow
//
//  AMA-2336 — mapper-api enrichment endpoints (spec 2026-07-27 §5).
//
//  Endpoints (mapper `baseURL`, not the BFF — `api/routers/enrichment.py`):
//    GET  /user/workout-preferences
//    PUT  /user/workout-preferences
//    POST /workout/enrich
//

import Foundation

extension APIService {
    /// GET `/user/workout-preferences` — stored prefs, defaults-filled by the backend.
    func fetchWorkoutPreferences() async throws -> WorkoutPreferences {
        let request = try await makeAPIRequest(
            baseURL: baseURL,
            path: "/user/workout-preferences",
            method: "GET"
        )
        return try await self.request(
            request,
            decode: WorkoutPreferences.self,
            decoder: WorkoutEnrichmentJSON.decoder,
            successStatusCodes: 200...200
        )
    }

    /// PUT `/user/workout-preferences`.
    ///
    /// The backend merges section-wise, so a full prefs body is also a valid patch.
    /// `rest_sec` is omitted when nil, which is what `rest_open == true` requires
    /// (contradictory intent is a 400, never a silent drop).
    @discardableResult
    func updateWorkoutPreferences(_ prefs: WorkoutPreferences) async throws -> WorkoutPreferences {
        let request = try await makeAPIRequest(
            baseURL: baseURL,
            path: "/user/workout-preferences",
            method: "PUT",
            body: try encodeJSONBody(prefs, encoder: WorkoutEnrichmentJSON.encoder)
        )
        return try await self.request(
            request,
            decode: WorkoutPreferences.self,
            decoder: WorkoutEnrichmentJSON.decoder,
            successStatusCodes: 200...200
        )
    }

    /// POST `/workout/enrich` — the only enrichment mutator. Callers own tombstones
    /// and persistence; `blocks_json` stays untyped through the round trip.
    func enrichWorkout(_ enrich: EnrichRequest) async throws -> EnrichResponse {
        let request = try await makeAPIRequest(
            baseURL: baseURL,
            path: "/workout/enrich",
            method: "POST",
            body: try enrich.jsonData()
        )
        let data = try await requestData(request, successStatusCodes: 200...200)
        return try EnrichResponse.from(data: data)
    }

    /// GET `/workouts/{id}` → stored `workout_data`.
    ///
    /// The push sheet enriches the **stored** payload rather than rebuilding it
    /// from the decoded `Workout`: that model drops `type`, `exercise_id` and
    /// `warmup_sets`, so a rebuild would both mis-read presence and erase
    /// declared fields on the way back in.
    func fetchWorkoutBlocksJSON(workoutId: String) async throws -> [String: Any] {
        let encodedID = workoutId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workoutId
        let request = try await makeAPIRequest(
            baseURL: baseURL,
            path: "/workouts/\(encodedID)",
            method: "GET"
        )
        let data = try await requestData(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let workout = root["workout"] as? [String: Any],
              let workoutData = workout["workout_data"] as? [String: Any] else {
            throw APIError.notFound
        }
        return workoutData
    }

    /// POST `/workouts/save` with an enriched `workout_data` verbatim.
    ///
    /// Used after `/workout/enrich` on the push path: FIT is generated when the
    /// CIQ widget downloads, so the enriched structure has to be the stored one.
    func saveWorkoutBlocksJSON(
        workoutId: String,
        title: String,
        blocksJSON: [String: Any],
        tombstones: [EnrichmentTombstone]? = nil
    ) async throws {
        var body: [String: Any] = [
            "workout_data": Self.saveableWorkoutData(
                blocksJSON,
                title: title,
                tombstones: tombstones
            ),
            "device": "ios",
            "title": title,
            "workout_id": workoutId
        ]
        if let sources = (blocksJSON["metadata"] as? [String: Any])?["sources"] as? [String] {
            body["sources"] = sources
        }
        let request = try await makeAPIRequest(
            baseURL: baseURL,
            path: "/workouts/save",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        try await requestVoid(request)
    }

    /// `SaveWorkoutRequest.workout_data` is strict + `extra="forbid"`, so anything
    /// outside its declared keys is a 422. Tombstones ride under `metadata`
    /// until WorkoutData declares a top-level field.
    static func saveableWorkoutData(
        _ workoutData: [String: Any],
        title: String,
        tombstones: [EnrichmentTombstone]? = nil
    ) -> [String: Any] {
        let allowed: Set<String> = [
            "title", "description", "duration", "duration_minutes",
            "type", "workout_type", "sport", "blocks", "intervals", "metadata"
        ]
        var sanitized = workoutData.filter { allowed.contains($0.key) }
        sanitized["title"] = title
        sanitized.removeValue(forKey: "enrichment_tombstones")

        var metadata = (sanitized["metadata"] as? [String: Any]) ?? [:]
        // Drop a stale top-level copy that may have been mirrored into metadata.
        if let tombstones {
            if tombstones.isEmpty {
                metadata.removeValue(forKey: "enrichment_tombstones")
            } else if let payload = try? EnrichmentTombstone.metadataPayload(tombstones) {
                metadata["enrichment_tombstones"] = payload
            }
        } else if let topLevel = workoutData["enrichment_tombstones"] {
            // Promote a top-level payload (from enrich echo / fixtures) into metadata.
            metadata["enrichment_tombstones"] = topLevel
        }
        if metadata.isEmpty {
            sanitized.removeValue(forKey: "metadata")
        } else {
            sanitized["metadata"] = metadata
        }
        return sanitized
    }
}
