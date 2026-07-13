//
//  APIService+Workout.swift
//  AmakaFlow
//
//  AMA-1828: workout-domain endpoints split out of APIService.swift.
//  Implemented as `extension APIService` so call sites stay unchanged
//  and APIServiceProviding conformance keeps working. Pure refactor.
//
//  Endpoints in this file:
//    GET    /workouts/incoming                    (fetchWorkouts)
//    GET    /workouts/pushed?device=…             (fetchPushedWorkouts)
//    GET    {bff}/v1/workouts/planned             (fetchScheduledWorkouts)
//    GET    {bff}/v1/sync/pending?device_type=…   (fetchPendingWorkouts)
//    POST   /workouts                             (syncWorkout)
//    POST   {bff}/v1/workouts/complete            (postWorkoutCompletion)
//    POST   {bff}/v1/sync/confirm                 (confirmSync)
//    POST   {bff}/v1/sync/failed                  (reportSyncFailed)
//    GET    /export/apple/{id}                    (getAppleExport)
//    POST   /workouts/completions                 (logManualWorkout)
//    GET    /workouts/completions                 (fetchCompletions)
//    GET    /workouts/completions/{id}            (fetchCompletionDetail)
//    POST   /workouts/save                        (saveWorkout)
//    GET    /workouts/{id}/export/fit             (exportWorkoutFIT)
//    GET    /workouts/{id}/export/csv             (exportWorkoutCSV)
//

import Foundation
import Sentry

extension APIService {

    // MARK: - Workouts

    /// Fetch workouts from backend
    func fetchWorkouts(isRetry: Bool = false) async throws -> [Workout] {
        guard PairingService.shared.isPaired else {
            print("[APIService] Not paired, throwing unauthorized")
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/workouts/incoming")!
        print("[APIService] Fetching incoming workouts from: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[APIService] Invalid response type")
            throw APIError.invalidResponse
        }

        print("[APIService] Response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            do {
                let workouts = try APIService.decodeIncomingWorkouts(from: data)
                print("[APIService] Decoded \(workouts.count) incoming workouts")
                return workouts
            } catch {
                print("[APIService] Decoding error: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[APIService] Response body: \(responseString.prefix(500))")
                }
                throw APIError.decodingError(error)
            }
        case 401:
            print("[APIService] Unauthorized (401)")
            guard !isRetry else { throw APIError.unauthorized }
            let refreshed = await PairingService.shared.refreshToken()
            if refreshed {
                return try await fetchWorkouts(isRetry: true)
            }
            throw APIError.unauthorized
        default:
            if let responseString = String(data: data, encoding: .utf8) {
                print("[APIService] Error response: \(responseString.prefix(200))")
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch scheduled workouts from backend.
    /// AMA-1814 / AMA-1820: routes through mobile-bff `/v1/workouts/planned`.
    func fetchScheduledWorkouts(isRetry: Bool = false) async throws -> [ScheduledWorkout] {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate) ?? startDate
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = Calendar.current.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let queryItems = [
            URLQueryItem(name: "from", value: dayFormatter.string(from: startDate)),
            URLQueryItem(name: "to", value: dayFormatter.string(from: endDate))
        ]

        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/workouts/planned",
            queryItems: queryItems,
            method: "GET"
        )

        do {
            let plannedResponse = try await self.request(
                request,
                decode: PlannedWorkoutListDTO.self,
                successStatusCodes: 200...200
            )
            return plannedResponse.workouts.map(ScheduledWorkout.init(plannedWorkout:))
        } catch APIError.unauthorized where !isRetry {
            let refreshed = await PairingService.shared.refreshToken()
            if refreshed {
                return try await fetchScheduledWorkouts(isRetry: true)
            }
            throw APIError.unauthorized
        }
    }

    /// Fetch workouts that have been pushed to this device
    func fetchPushedWorkouts(isRetry: Bool = false) async throws -> [Workout] {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let request = try await makeAPIRequest(
            path: "/workouts/pushed",
            queryItems: [URLQueryItem(name: "device", value: "ios-companion")],
            method: "GET"
        )

        do {
            return try await self.request(
                request,
                decode: [Workout].self,
                successStatusCodes: 200...200
            )
        } catch APIError.unauthorized where !isRetry {
            let refreshed = await PairingService.shared.refreshToken()
            if refreshed {
                return try await fetchPushedWorkouts(isRetry: true)
            }
            throw APIError.unauthorized
        }
    }

    /// Fetch pending workouts from sync queue endpoint (AMA-307 / AMA-1820).
    func fetchPendingWorkouts(isRetry: Bool = false) async throws -> [Workout] {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/sync/pending",
            queryItems: [URLQueryItem(name: "device_type", value: "ios")],
            method: "GET"
        )

        do {
            let pendingResponse = try await self.request(
                request,
                decode: PendingWorkoutsResponse.self,
                successStatusCodes: 200...200
            )
            guard pendingResponse.success else {
                throw APIError.serverErrorWithBody(200, "GET /sync/pending returned success=false")
            }
            return pendingResponse.workouts
        } catch APIError.unauthorized where !isRetry {
            let refreshed = await PairingService.shared.refreshToken()
            if refreshed {
                return try await fetchPendingWorkouts(isRetry: true)
            }
            throw APIError.unauthorized
        }
    }

    /// Sync workout to backend (POST /workouts).
    func syncWorkout(_ workout: Workout) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/workouts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(workout)

        print("[APIService] syncWorkout - URL: \(url.absoluteString)")
        print("[APIService] syncWorkout - Workout: \(workout.name)")

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[APIService] syncWorkout - Status: \(httpResponse.statusCode)")
        print("[APIService] syncWorkout - Response: \(responseString ?? "nil")")

        if httpResponse.statusCode >= 400 {
            await DebugLogService.shared.logAPIError(
                endpoint: "/workouts",
                method: "POST",
                statusCode: httpResponse.statusCode,
                response: responseString
            )
        }

        switch httpResponse.statusCode {
        case 200, 201:
            return
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Get workout export in Apple WorkoutKit format
    func getAppleExport(workoutId: String) async throws -> String {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let encodedWorkoutID = try Self.pathSegment(workoutId)
        let request = try await makeAPIRequest(
            path: "/export/apple/\(encodedWorkoutID)",
            method: "GET"
        )
        let data = try await requestData(request, successStatusCodes: 200...200)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw APIError.decodingError(
                NSError(
                    domain: "APIService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode response"]
                )
            )
        }
        return jsonString
    }

    // MARK: - Manual Workout Logging (AMA-5)

    /// Log a manually-recorded workout completion to activity history.
    func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/workouts/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let intervalsData = try encoder.encode(workout.intervals)
        let intervalsJSON = try JSONSerialization.jsonObject(with: intervalsData)

        let body: [String: Any] = [
            "workout": [
                "id": workout.id,
                "name": workout.name,
                "sport": workout.sport.rawValue,
                "duration": workout.duration,
                "intervals": intervalsJSON,
                "description": workout.description as Any,
                "source": "ai"
            ],
            "completion": [
                "started_at": formatter.string(from: startedAt),
                "ended_at": formatter.string(from: endedAt),
                "duration_seconds": durationSeconds,
                "source": "manual"
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[APIService] logManualWorkout - URL: \(url.absoluteString)")
        print("[APIService] logManualWorkout - Workout: \(workout.name) with \(workout.intervals.count) intervals")

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[APIService] logManualWorkout - Status: \(httpResponse.statusCode)")
        print("[APIService] logManualWorkout - Response: \(responseString ?? "nil")")

        if httpResponse.statusCode >= 400 {
            await DebugLogService.shared.logAPIError(
                endpoint: "/workouts/completions",
                method: "POST",
                statusCode: httpResponse.statusCode,
                response: responseString
            )
        }

        switch httpResponse.statusCode {
        case 200, 201:
            return
        case 401:
            throw APIError.unauthorized
        case 404, 405:
            print("[APIService] logManualWorkout - Endpoint not available (\(httpResponse.statusCode))")
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseString ?? "Endpoint not available")
        default:
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseString ?? "Unknown error")
        }
    }

    // MARK: - Workout Completion (AMA-1820 — bff route)

    /// Post workout completion to backend
    func postWorkoutCompletion(
        _ completion: WorkoutCompletionRequest,
        isRetry: Bool = false,
        requestID: String? = nil
    ) async throws -> WorkoutCompletionResponse {
        let endpoint = "/workouts/complete"

        #if DEBUG
        let hasAuth = PairingService.shared.isPaired
        #else
        let hasAuth = PairingService.shared.isPaired
        #endif

        guard hasAuth else {
            print("[APIService] Not paired and not in E2E test mode, throwing unauthorized")
            logError(endpoint: endpoint, method: "POST", statusCode: nil, response: nil, error: APIError.unauthorized)
            throw APIError.unauthorized
        }

        var request = try await makeAPIRequest(
            baseURL: bffURL,
            path: endpoint,
            method: "POST",
            body: try encodeJSONBody(completion)
        )

        // AMA-1823: stamp client-generated X-Request-ID so the BFF echoes
        // it through to mapper-api logs and Sentry breadcrumbs share the
        // same correlation key.
        if let requestID = requestID {
            request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        }

        do {
            let completionResponse = try await self.request(
                request,
                decode: WorkoutCompletionResponse.self,
                successStatusCodes: 200...201
            )

            if completionResponse.success == false {
                throw AnnotatedAPIError(
                    .serverErrorWithBody(200, "POST /workouts/complete returned success=false")
                )
            }

            guard completionResponse.hasResolvedCompletionId else {
                throw AnnotatedAPIError(
                    .serverErrorWithBody(200, "POST /workouts/complete missing completion ID")
                )
            }

            return completionResponse
        } catch APIError.unauthorized where !isRetry {
            let refreshed = await PairingService.shared.refreshToken()
            if refreshed {
                return try await postWorkoutCompletion(completion, isRetry: true, requestID: requestID)
            }
            await MainActor.run {
                PairingService.shared.markAuthInvalid()
            }
            SentrySDK.capture(message: "auth.silent_refresh_failed") { scope in
                scope.setTag(value: "auth", key: "subsystem")
                scope.setTag(value: endpoint, key: "endpoint")
                if let requestID {
                    scope.setTag(value: requestID, key: "request_id")
                }
                scope.setLevel(SentryLevel.warning)
            }
            throw AnnotatedAPIError(.unauthorized, requestId: requestID)
        } catch let apiError as APIError {
            throw AnnotatedAPIError(apiError, requestId: requestID)
        }
    }

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

        let url = URL(string: "\(bffURL)/sync/confirm")!
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

        let url = URL(string: "\(bffURL)/sync/failed")!
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

    // MARK: - Workout Editor (AMA-1231)

    /// Save a new or edited workout
    func saveWorkout(_ request: WorkoutSaveRequest) async throws -> Workout {
        // AMA-2285: provenance-aware path lives in APIService+SocialImport.
        if let source = request.source, !source.isEmpty {
            return try await saveWorkoutWithProvenance(request, source: source)
        }

        guard let url = URL(string: "\(baseURL)/workouts/save") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.allHTTPHeaderFields = try await makeAuthHeaders()

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(httpResponse.statusCode)
        }
        return try APIService.makeDecoder().decode(Workout.self, from: data)
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
