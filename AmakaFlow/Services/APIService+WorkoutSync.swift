//
//  APIService+WorkoutSync.swift
//  AmakaFlow
//
//  Sync confirmation, completion history, library delete, editor save, export.
//  Split from APIService+Workout.swift for SwiftLint file_length.
//

import Foundation

extension APIService {
    // MARK: - Sync Confirmation (AMA-307 / AMA-1820)

    /// Confirm that a workout was successfully synced/downloaded to this device
    func confirmSync(
        workoutId: String,
        deviceType: String = "ios",
        deviceId: String? = nil,
        requestID: String? = nil
    ) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        guard let url = URL(string: "\(bffURL)/sync/confirm") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        if let requestID = requestID {
            request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        }

        var body: [String: Any] = [
            "workout_id": workoutId,
            "device_type": deviceType
        ]
        if let deviceId = deviceId {
            body["device_id"] = deviceId
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[APIService] Confirming sync for workout \(workoutId)")

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[APIService] Confirm sync response: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200, 201:
            print("[APIService] Sync confirmed for workout \(workoutId)")
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            print("[APIService] No sync queue entry found for workout \(workoutId) - may already be confirmed")
            return
        default:
            logError(endpoint: "/sync/confirm", method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Report that a workout sync/download failed
    func reportSyncFailed(
        workoutId: String,
        deviceType: String = "ios",
        error: String,
        deviceId: String? = nil,
        requestID: String? = nil
    ) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        guard let url = URL(string: "\(bffURL)/sync/failed") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        if let requestID = requestID {
            request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        }

        var body: [String: Any] = [
            "workout_id": workoutId,
            "device_type": deviceType,
            "error": error
        ]
        if let deviceId = deviceId {
            body["device_id"] = deviceId
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[APIService] Reporting sync failure for workout \(workoutId): \(error)")

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[APIService] Report sync failed response: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200, 201:
            print("[APIService] Sync failure reported for workout \(workoutId)")
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            print("[APIService] No sync queue entry found for workout \(workoutId)")
            return
        default:
            logError(endpoint: "/sync/failed", method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Completion History

    func fetchCompletions(limit: Int = 50, offset: Int = 0) async throws -> [WorkoutCompletion] {
        let request = try await makeAPIRequest(
            path: "/workouts/completions",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ],
            method: "GET"
        )

        let wrapped = try await self.request(
            request,
            decode: CompletionsListResponse.self,
            successStatusCodes: 200...200
        )
        guard wrapped.success else {
            throw APIError.serverErrorWithBody(200, "GET /workouts/completions returned success=false")
        }
        return wrapped.completions
    }

    func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail {
        let encodedID = try Self.pathSegment(id)
        let request = try await makeAPIRequest(
            path: "/workouts/completions/\(encodedID)",
            method: "GET"
        )
        let wrapped = try await self.request(
            request,
            decode: CompletionDetailWrappedResponse.self,
            successStatusCodes: 200...200
        )
        guard wrapped.success else {
            throw APIError.serverErrorWithBody(200, "GET /workouts/completions/{id} returned success=false")
        }
        return wrapped.completion
    }

    // MARK: - Library workout delete (AMA-2298)

    /// Delete a saved workout import (mapper-api `DELETE /workouts/{workout_id}`).
    func deleteWorkout(id: String) async throws {
        let encodedID = try Self.pathSegment(id)
        let request = try await makeAPIRequest(
            path: "/workouts/\(encodedID)",
            method: "DELETE"
        )
        try await requestVoid(request, successStatusCodes: 200...299)
    }

    // MARK: - Workout Editor (AMA-1231)

    /// Save a new or edited workout via mapper `workout_data` + `device` body.
    /// Always uses the provenance-compatible path (AMA-2285 / editor persist fix).
    func saveWorkout(_ request: WorkoutSaveRequest) async throws -> Workout {
        let trimmedSource = request.source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSource = trimmedSource.flatMap { $0.isEmpty ? nil : $0 }
            ?? WorkoutSource.manual.rawValue
        return try await saveWorkoutWithProvenance(request, source: resolvedSource)
    }

    // MARK: - Workout Export (AMA-1231)

    /// Export workout as FIT binary data
    func exportWorkoutFIT(workoutId: String) async throws -> Data {
        let encodedWorkoutID = try Self.pathSegment(workoutId)
        let request = try await makeAPIRequest(
            path: "/workouts/\(encodedWorkoutID)/export/fit",
            method: "GET"
        )
        return try await requestData(request, successStatusCodes: 200...200)
    }

    /// Export workout as CSV data
    func exportWorkoutCSV(workoutId: String) async throws -> Data {
        let encodedWorkoutID = try Self.pathSegment(workoutId)
        let request = try await makeAPIRequest(
            path: "/workouts/\(encodedWorkoutID)/export/csv",
            method: "GET"
        )
        return try await requestData(request, successStatusCodes: 200...200)
    }
}
