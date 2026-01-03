//
//  APIService.swift
//  AmakaFlow
//
//  API service for fetching workouts from mapper-api
//

import Foundation

/// Service for API communication with backend
class APIService {
    static let shared = APIService()

    private let baseURL = AppEnvironment.current.mapperAPIURL
    private let session = URLSession.shared

    private init() {}

    // MARK: - Shared JSON Decoder

    /// Create a JSONDecoder configured for our API responses
    /// Handles ISO8601 dates both with and without fractional seconds
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first (e.g., "2026-01-02T02:41:21.295+00:00")
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractional.date(from: dateString) {
                return date
            }

            // Fall back to standard ISO8601 (e.g., "2025-01-01T10:00:00Z")
            let formatterStandard = ISO8601DateFormatter()
            formatterStandard.formatOptions = [.withInternetDateTime]
            if let date = formatterStandard.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }

    // MARK: - Error Logging Helper

    private func logError(endpoint: String, method: String, statusCode: Int?, response: String?, error: Error?) {
        Task { @MainActor in
            // Log to debug service
            DebugLogService.shared.logAPIError(
                endpoint: endpoint,
                method: method,
                statusCode: statusCode,
                response: response,
                error: error
            )

            // Capture to Sentry (AMA-225)
            let apiError = error ?? APIError.serverError(statusCode ?? 0)
            SentryService.shared.captureAPIError(
                apiError,
                endpoint: "\(method) \(endpoint)",
                statusCode: statusCode,
                responseBody: response
            )
        }
    }

    // MARK: - Auth Headers

    private var authHeaders: [String: String] {
        var headers = ["Content-Type": "application/json"]
        if let token = PairingService.shared.getToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    // MARK: - Workouts

    /// Fetch workouts from backend
    /// - Returns: Array of workouts
    /// - Throws: APIError if request fails
    func fetchWorkouts() async throws -> [Workout] {
        guard PairingService.shared.isPaired else {
            print("[APIService] Not paired, throwing unauthorized")
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/workouts")!
        print("[APIService] Fetching workouts from: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[APIService] Invalid response type")
            throw APIError.invalidResponse
        }

        print("[APIService] Response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let workouts = try decoder.decode([Workout].self, from: data)
                print("[APIService] Decoded \(workouts.count) workouts")
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
            throw APIError.unauthorized
        default:
            if let responseString = String(data: data, encoding: .utf8) {
                print("[APIService] Error response: \(responseString.prefix(200))")
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch scheduled workouts from backend
    /// - Returns: Array of scheduled workouts
    /// - Throws: APIError if request fails
    func fetchScheduledWorkouts() async throws -> [ScheduledWorkout] {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/workouts/scheduled")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = APIService.makeDecoder()
            return try decoder.decode([ScheduledWorkout].self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            // Endpoint may not exist yet, return empty array
            return []
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch workouts that have been pushed to this device
    /// - Returns: Array of workouts
    /// - Throws: APIError if request fails
    func fetchPushedWorkouts() async throws -> [Workout] {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/workouts/pushed?device=ios-companion")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode([Workout].self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            // Endpoint may not exist yet, return empty array
            return []
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch pending workouts from iOS companion endpoint
    /// - Returns: Array of pending workouts
    /// - Throws: APIError if request fails
    func fetchPendingWorkouts() async throws -> [Workout] {
        guard PairingService.shared.isPaired else {
            print("[APIService] Not paired, throwing unauthorized")
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/ios-companion/pending")!
        print("[APIService] Fetching pending workouts from: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[APIService] Invalid response type")
            throw APIError.invalidResponse
        }

        print("[APIService] Response status: \(httpResponse.statusCode)")

        // Debug: Print raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("[APIService] Raw JSON response (first 1000 chars):")
            print(String(jsonString.prefix(1000)))
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = APIService.makeDecoder()
            do {
                let pendingResponse = try decoder.decode(PendingWorkoutsResponse.self, from: data)
                print("[APIService] Decoded \(pendingResponse.count) pending workouts")
                // Debug: Print first workout's intervals
                if let firstWorkout = pendingResponse.workouts.first {
                    print("[APIService] First workout: \(firstWorkout.name)")
                    print("[APIService] Intervals: \(firstWorkout.intervals.count)")
                    for (i, interval) in firstWorkout.intervals.enumerated() {
                        if case .reps(let sets, let reps, let name, _, let restSec, _) = interval {
                            print("[APIService]   Interval \(i): reps '\(name)' sets=\(sets ?? -1) reps=\(reps) restSec=\(restSec ?? -999)")
                        }
                    }
                }
                return pendingResponse.workouts
            } catch {
                print("[APIService] Decoding error: \(error)")
                throw APIError.decodingError(error)
            }
        case 401:
            print("[APIService] Unauthorized (401)")
            throw APIError.unauthorized
        case 404:
            // Endpoint may not exist yet, return empty array
            print("[APIService] Endpoint not found, returning empty array")
            return []
        default:
            if let responseString = String(data: data, encoding: .utf8) {
                print("[APIService] Error response: \(responseString.prefix(200))")
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Sync workout to backend
    /// - Parameter workout: Workout to sync/create
    /// - Throws: APIError if sync fails
    func syncWorkout(_ workout: Workout) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        // Use POST /workouts to create the workout
        let url = URL(string: "\(baseURL)/workouts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

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

        // Log errors to DebugLogService
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
    /// - Parameter workoutId: ID of workout to export
    /// - Returns: JSON string in WKPlanDTO format
    /// - Throws: APIError if export fails
    func getAppleExport(workoutId: String) async throws -> String {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/export/apple/\(workoutId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw APIError.decodingError(NSError(domain: "APIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to decode response"]))
            }
            return jsonString
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Voice Workout Parsing (AMA-5)

    /// Parse a voice transcription into a structured workout
    /// - Parameters:
    ///   - transcription: The transcribed text from voice recording
    ///   - sportHint: Optional hint about the sport type
    /// - Returns: Parsed workout response with confidence and suggestions
    /// - Throws: APIError if request fails
    func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport? = nil) async throws -> VoiceWorkoutParseResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        // Voice parsing is on the ingestor API, not the mapper API
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let url = URL(string: "\(ingestorURL)/workouts/parse-voice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

        var body: [String: Any] = ["transcription": transcription]
        if let hint = sportHint {
            body["sport_hint"] = hint.rawValue
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[APIService] parseVoiceWorkout - URL: \(url.absoluteString)")
        print("[APIService] parseVoiceWorkout - Body: \(body)")

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[APIService] parseVoiceWorkout - Status: \(httpResponse.statusCode)")
        print("[APIService] parseVoiceWorkout - Response: \(responseString ?? "nil")")

        // Log errors to DebugLogService
        if httpResponse.statusCode >= 400 {
            await DebugLogService.shared.logAPIError(
                endpoint: "/workouts/parse-voice",
                method: "POST",
                statusCode: httpResponse.statusCode,
                response: responseString
            )
        }

        switch httpResponse.statusCode {
        case 200, 201:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let parseResponse = try decoder.decode(VoiceWorkoutParseResponse.self, from: data)
                print("[APIService] Parsed workout: \(parseResponse.workout.name)")
                return parseResponse
            } catch {
                print("[APIService] Decoding error: \(error)")
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 422:
            // Validation error - could not parse the transcription
            throw APIError.serverErrorWithBody(422, responseString ?? "Could not understand workout description")
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Cloud Transcription (AMA-229)

    /// Request cloud transcription using specified provider
    /// - Parameters:
    ///   - audioData: Base64 encoded audio data
    ///   - provider: Transcription provider (deepgram or assemblyai)
    ///   - language: Language/accent code (e.g., "en-US")
    ///   - keywords: Optional keywords for boosting
    ///   - includeWordTimings: Whether to include word-level timings
    /// - Returns: CloudTranscriptionResponse with text and confidence
    /// - Throws: APIError if request fails
    func transcribeAudio(
        audioData: String,
        provider: String,
        language: String,
        keywords: [String],
        includeWordTimings: Bool
    ) async throws -> CloudTranscriptionResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let url = URL(string: "\(ingestorURL)/voice/transcribe")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

        let body: [String: Any] = [
            "audio": audioData,
            "provider": provider,
            "language": language,
            "keywords": keywords,
            "include_word_timings": includeWordTimings
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            await DebugLogService.shared.logAPIError(
                endpoint: "/voice/transcribe",
                method: "POST",
                statusCode: httpResponse.statusCode,
                response: responseString
            )
        }

        switch httpResponse.statusCode {
        case 200, 201:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(CloudTranscriptionResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Personal Dictionary Sync (AMA-229)

    /// Sync personal dictionary with backend
    func syncPersonalDictionary(
        corrections: [String: String],
        customTerms: [String]
    ) async throws -> PersonalDictionaryResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let url = URL(string: "\(ingestorURL)/voice/dictionary")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

        let body: [String: Any] = [
            "corrections": corrections,
            "custom_terms": customTerms
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 201:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(PersonalDictionaryResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch personal dictionary from backend
    func fetchPersonalDictionary() async throws -> PersonalDictionaryResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let url = URL(string: "\(ingestorURL)/voice/dictionary")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(PersonalDictionaryResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Manual Workout Logging (AMA-5)

    /// Log a manually-recorded workout completion to activity history
    /// Creates both a Workout record (with exercise details) and a Completion record
    /// - Parameters:
    ///   - workout: The parsed workout with full interval details
    ///   - startedAt: When the workout started
    ///   - endedAt: When the workout ended
    ///   - durationSeconds: Total duration in seconds
    /// - Throws: APIError if request fails
    func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/workouts/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

        // Build request body with full workout details
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Encode workout intervals to JSON
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let intervalsData = try encoder.encode(workout.intervals)
        let intervalsJSON = try JSONSerialization.jsonObject(with: intervalsData)

        let body: [String: Any] = [
            // Workout details
            "workout": [
                "id": workout.id,
                "name": workout.name,
                "sport": workout.sport.rawValue,
                "duration": workout.duration,
                "intervals": intervalsJSON,
                "description": workout.description as Any,
                "source": "ai"
            ],
            // Completion details
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

        // Log errors to DebugLogService
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
            // Endpoint may not exist yet - log but don't fail for MVP
            print("[APIService] logManualWorkout - Endpoint not available (\(httpResponse.statusCode))")
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseString ?? "Endpoint not available")
        default:
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseString ?? "Unknown error")
        }
    }

    // MARK: - Workout Completion

    /// Post workout completion to backend
    /// - Parameter completion: Workout completion request with health metrics
    /// - Returns: Completion response with ID
    /// - Throws: APIError if request fails
    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool = false) async throws -> WorkoutCompletionResponse {
        let endpoint = "/workouts/complete"

        guard PairingService.shared.isPaired else {
            print("[APIService] Not paired, throwing unauthorized")
            logError(endpoint: endpoint, method: "POST", statusCode: nil, response: nil, error: APIError.unauthorized)
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)\(endpoint)")!
        print("[APIService] Posting workout completion to: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(completion)

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[APIService] Invalid response type")
            logError(endpoint: endpoint, method: "POST", statusCode: nil, response: responseString, error: APIError.invalidResponse)
            throw APIError.invalidResponse
        }

        print("[APIService] Response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200, 201:
            let decoder = JSONDecoder()
            do {
                let completionResponse = try decoder.decode(WorkoutCompletionResponse.self, from: data)
                print("[APIService] Workout completion posted, ID: \(completionResponse.resolvedCompletionId)")
                return completionResponse
            } catch {
                print("[APIService] Decoding error: \(error)")
                if let responseString = responseString {
                    print("[APIService] Response body: \(responseString.prefix(500))")
                }
                // Log if backend returned success:false (HTTP 200 but logical failure)
                if let responseString = responseString, responseString.contains("\"success\":false") {
                    logError(endpoint: endpoint, method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
                }
                throw APIError.decodingError(error)
            }
        case 401:
            print("[APIService] Unauthorized (401)")

            // If this is already a retry, don't try again
            if isRetry {
                print("[APIService] Retry also failed with 401, marking auth invalid")
                logError(endpoint: endpoint, method: "POST", statusCode: 401, response: responseString, error: APIError.unauthorized)
                await MainActor.run {
                    PairingService.shared.markAuthInvalid()
                }
                throw APIError.unauthorized
            }

            // Try to silently refresh the token
            print("[APIService] Attempting silent token refresh...")
            let refreshed = await PairingService.shared.refreshToken()

            if refreshed {
                print("[APIService] Token refreshed, retrying request...")
                // Retry the request with new token
                return try await postWorkoutCompletion(completion, isRetry: true)
            } else {
                // Refresh failed - device not found or needs re-pair
                print("[APIService] Token refresh failed, marking auth invalid")
                logError(endpoint: endpoint, method: "POST", statusCode: 401, response: responseString, error: APIError.unauthorized)
                throw APIError.unauthorized
            }
        default:
            if let responseString = responseString {
                print("[APIService] Error response: \(responseString.prefix(200))")
            }
            logError(endpoint: endpoint, method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Pending Workouts Response
struct PendingWorkoutsResponse: Codable {
    let success: Bool
    let workouts: [Workout]
    let count: Int
}

// MARK: - Voice Workout Parse Response (AMA-5)
struct VoiceWorkoutParseResponse: Codable {
    let success: Bool
    let workout: Workout
    let confidence: Double
    let suggestions: [String]
}

// MARK: - Cloud Transcription Response (AMA-229)

struct CloudTranscriptionResponse: Codable {
    let text: String
    let confidence: Double
    let words: [CloudWordTiming]?
    let provider: String
    let durationMs: Int?
}

struct CloudWordTiming: Codable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double?
}

// MARK: - Personal Dictionary Response (AMA-229)

struct PersonalDictionaryResponse: Codable {
    let corrections: [String: String]
    let customTerms: [String]
}

// MARK: - API Errors
enum APIError: LocalizedError {
    case notImplemented
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case notFound
    case serverError(Int)
    case serverErrorWithBody(Int, String)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "API feature not yet implemented"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unauthorized:
            return "Session expired. Please reconnect."
        case .notFound:
            return "Resource not found"
        case .serverError(let code):
            return "Server error: \(code)"
        case .serverErrorWithBody(let code, let body):
            return "Server error \(code): \(body)"
        }
    }
}
