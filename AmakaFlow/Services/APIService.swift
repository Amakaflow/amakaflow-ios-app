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

    private var baseURL: String { AppEnvironment.current.mapperAPIURL }
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

        // E2E Test mode: Use X-Test-Auth header bypass instead of JWT
        // This checks both environment variables AND stored credentials from UI
        #if DEBUG
        if let testAuthSecret = TestAuthStore.shared.authSecret,
           let testUserId = TestAuthStore.shared.userId,
           !testAuthSecret.isEmpty {
            headers["X-Test-Auth"] = testAuthSecret
            headers["X-Test-User-Id"] = testUserId
            print("[APIService] Using X-Test-Auth header bypass for E2E tests")
            return headers
        }
        #endif

        // Normal auth: Use JWT token
        if let token = PairingService.shared.getToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    // MARK: - Workouts

    /// Fetch workouts from backend
    /// - Returns: Array of workouts
    /// - Throws: APIError if request fails
    func fetchWorkouts(isRetry: Bool = false) async throws -> [Workout] {
        guard PairingService.shared.isPaired else {
            print("[APIService] Not paired, throwing unauthorized")
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/workouts/incoming")!
        print("[APIService] Fetching incoming workouts from: \(url)")

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

    /// Fetch scheduled workouts from backend
    /// - Returns: Array of scheduled workouts
    /// - Throws: APIError if request fails
    func fetchScheduledWorkouts(isRetry: Bool = false) async throws -> [ScheduledWorkout] {
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
            guard !isRetry else { throw APIError.unauthorized }
            let refreshed = await PairingService.shared.refreshToken()
            if refreshed {
                return try await fetchScheduledWorkouts(isRetry: true)
            }
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
    func fetchPushedWorkouts(isRetry: Bool = false) async throws -> [Workout] {
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
            guard !isRetry else { throw APIError.unauthorized }
            let refreshed = await PairingService.shared.refreshToken()
            if refreshed {
                return try await fetchPushedWorkouts(isRetry: true)
            }
            throw APIError.unauthorized
        case 404:
            // Endpoint may not exist yet, return empty array
            return []
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Fetch pending workouts from sync queue endpoint (AMA-307)
    /// Uses the new /sync/pending endpoint which tracks proper sync state
    /// - Returns: Array of pending workouts
    /// - Throws: APIError if request fails
    func fetchPendingWorkouts(isRetry: Bool = false) async throws -> [Workout] {
        guard PairingService.shared.isPaired else {
            print("[APIService] Not paired, throwing unauthorized")
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/sync/pending?device_type=ios")!
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
            guard !isRetry else { throw APIError.unauthorized }
            let refreshed = await PairingService.shared.refreshToken()
            if refreshed {
                return try await fetchPendingWorkouts(isRetry: true)
            }
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

    // MARK: - Instagram Reel Ingestion (AMA-564)

    /// Ingest an Instagram Reel URL and return structured workout data
    /// - Parameter url: The Instagram Reel URL to ingest
    /// - Returns: IngestInstagramReelResponse with title and workout type
    /// - Throws: APIError if request fails
    func ingestInstagramReel(url: String) async throws -> IngestInstagramReelResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let requestURL = URL(string: "\(ingestorURL)/ingest/instagram_reel")!
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

        let body: [String: Any] = ["url": url]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[APIService] ingestInstagramReel - URL: \(requestURL.absoluteString)")

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[APIService] ingestInstagramReel - Status: \(httpResponse.statusCode)")
        print("[APIService] ingestInstagramReel - Response: \(responseString ?? "nil")")

        if httpResponse.statusCode >= 400 {
            await DebugLogService.shared.logAPIError(
                endpoint: "/ingest/instagram_reel",
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
                return try decoder.decode(IngestInstagramReelResponse.self, from: data)
            } catch {
                print("[APIService] ingestInstagramReel decoding error: \(error)")
                throw APIError.decodingError(error)
            }
        case 400:
            throw APIError.serverErrorWithBody(400, responseString ?? "Bad request")
        case 401:
            throw APIError.unauthorized
        case 422:
            throw APIError.serverErrorWithBody(422, responseString ?? "Could not process Instagram Reel")
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Text Ingestion (Manual Instagram Import)

    /// Ingest workout from plain text via the /ingest/text endpoint (multipart form)
    /// - Parameters:
    ///   - text: The workout description/caption text
    ///   - source: Optional source identifier (e.g. "instagram")
    /// - Returns: IngestTextResponse with parsed workout title and type
    /// - Throws: APIError if request fails
    func ingestText(text: String, source: String? = nil) async throws -> IngestTextResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let requestURL = URL(string: "\(ingestorURL)/ingest/text")!

        // Build multipart form body
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"

        // Use auth headers but override Content-Type for multipart
        var headers = authHeaders
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        request.allHTTPHeaderFields = headers

        var body = Data()

        // text field (required)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"text\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(text)\r\n".data(using: .utf8)!)

        // source field (optional)
        if let source = source {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"source\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(source)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        print("[APIService] ingestText - URL: \(requestURL.absoluteString)")

        let (data, response) = try await session.data(for: request)
        let responseString = String(data: data, encoding: .utf8)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[APIService] ingestText - Status: \(httpResponse.statusCode)")
        print("[APIService] ingestText - Response: \(responseString?.prefix(500) ?? "nil")")

        if httpResponse.statusCode >= 400 {
            await DebugLogService.shared.logAPIError(
                endpoint: "/ingest/text",
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
                return try decoder.decode(IngestTextResponse.self, from: data)
            } catch {
                print("[APIService] ingestText decoding error: \(error)")
                throw APIError.decodingError(error)
            }
        case 400:
            throw APIError.serverErrorWithBody(400, responseString ?? "Bad request")
        case 401:
            throw APIError.unauthorized
        case 422:
            throw APIError.serverErrorWithBody(422, responseString ?? "Could not parse workout text")
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

        // Check for valid auth - either pairing or E2E test mode
        #if DEBUG
        let hasAuth = PairingService.shared.isPaired || TestAuthStore.shared.isTestModeEnabled
        #else
        let hasAuth = PairingService.shared.isPaired
        #endif

        guard hasAuth else {
            print("[APIService] Not paired and not in E2E test mode, throwing unauthorized")
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
            // Log the raw response for debugging (AMA-271)
            let responseBody = responseString ?? "nil"
            print("[APIService] POST /workouts/complete response: \(responseBody.prefix(500))")
            Task { @MainActor in
                DebugLogService.shared.log(
                    "API: POST complete",
                    details: "Status: \(httpResponse.statusCode), Body: \(responseBody.prefix(300))",
                    metadata: nil
                )
            }

            // Check for success:false in response body - backend returns HTTP 200 but logical failure (AMA-271)
            if let responseString = responseString, responseString.contains("\"success\":false") {
                print("[APIService] Backend returned success:false - treating as error")
                logError(endpoint: endpoint, method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
                Task { @MainActor in
                    DebugLogService.shared.log(
                        "API: Completion FAILED",
                        details: "Backend error: \(responseBody.prefix(200))",
                        metadata: nil
                    )
                }
                throw APIError.serverErrorWithBody(httpResponse.statusCode, responseBody)
            }

            do {
                let completionResponse = try decoder.decode(WorkoutCompletionResponse.self, from: data)
                print("[APIService] Workout completion posted, ID: \(completionResponse.resolvedCompletionId)")
                return completionResponse
            } catch {
                print("[APIService] Decoding error: \(error)")
                if let responseString = responseString {
                    print("[APIService] Response body: \(responseString.prefix(500))")
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

    // MARK: - Sync Confirmation (AMA-307)

    /// Confirm that a workout was successfully synced/downloaded to this device
    /// - Parameters:
    ///   - workoutId: The workout ID that was synced
    ///   - deviceType: Device type (ios, android, garmin)
    ///   - deviceId: Optional device identifier
    /// - Throws: APIError if request fails
    func confirmSync(workoutId: String, deviceType: String = "ios", deviceId: String? = nil) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/sync/confirm")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

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
            // Queue entry not found - might have been already confirmed or doesn't exist
            print("[APIService] No sync queue entry found for workout \(workoutId) - may already be confirmed")
            return
        default:
            logError(endpoint: "/sync/confirm", method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Report that a workout sync/download failed
    /// - Parameters:
    ///   - workoutId: The workout ID that failed to sync
    ///   - deviceType: Device type (ios, android, garmin)
    ///   - error: Error message describing the failure
    ///   - deviceId: Optional device identifier
    /// - Throws: APIError if request fails
    func reportSyncFailed(workoutId: String, deviceType: String = "ios", error: String, deviceId: String? = nil) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/sync/failed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

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
            // Queue entry not found - log but don't fail
            print("[APIService] No sync queue entry found for workout \(workoutId)")
            return
        default:
            logError(endpoint: "/sync/failed", method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Push Token Registration (AMA-567)

    /// Register APNs push token with the backend for silent push notifications
    /// - Parameters:
    ///   - apnsToken: Hex-encoded APNs device token from Apple
    ///   - deviceId: iOS device UUID (identifierForVendor)
    /// - Throws: APIError if request fails
    func registerPushToken(apnsToken: String, deviceId: String) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/mobile/devices/register-push-token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

        let body: [String: Any] = [
            "apns_token": apnsToken,
            "device_id": deviceId,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[APIService] Registering push token")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 201:
            print("[APIService] Push token registered successfully")
            return
        case 401:
            throw APIError.unauthorized
        default:
            let responseString = String(data: data, encoding: .utf8)
            logError(endpoint: "/mobile/devices/register-push-token", method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - User Profile

    /// Fetch user profile from backend
    /// - Returns: UserProfile if successful
    /// - Throws: APIError if request fails
    func fetchProfile() async throws -> UserProfile {
        let url = URL(string: "\(baseURL)/mobile/profile")!
        print("[APIService] Fetching profile from: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[APIService] Invalid response type")
            throw APIError.invalidResponse
        }

        print("[APIService] Profile response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let profileResponse = try decoder.decode(ProfileResponse.self, from: data)
                print("[APIService] Fetched profile for: \(profileResponse.profile.name ?? profileResponse.profile.email ?? "unknown")")
                return profileResponse.profile
            } catch {
                print("[APIService] Profile decoding error: \(error)")
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

    // MARK: - Completion History

    func fetchCompletions(limit: Int = 50, offset: Int = 0) async throws -> [WorkoutCompletion] {
        let url = URL(string: "\(baseURL)/workouts/completions?limit=\(limit)&offset=\(offset)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "empty"
        print("[APIService] fetchCompletions - Status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            do {
                let wrapped = try Self.makeDecoder().decode(CompletionsListResponse.self, from: data)
                return wrapped.completions
            } catch {
                logError(endpoint: "/workouts/completions", method: "GET", statusCode: 200,
                         response: String(responseBody.prefix(500)), error: error)
                return []
            }
        case 401:
            throw APIError.unauthorized
        case 404, 500:
            return []
        default:
            logError(endpoint: "/workouts/completions", method: "GET", statusCode: httpResponse.statusCode,
                     response: responseBody, error: nil)
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseBody)
        }
    }

    func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail {
        let url = URL(string: "\(baseURL)/workouts/completions/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "empty"
        print("[APIService] fetchCompletionDetail(\(id)) - Status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            let wrapped = try Self.makeDecoder().decode(CompletionDetailWrappedResponse.self, from: data)
            return wrapped.completion
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            logError(endpoint: "/workouts/completions/\(id)", method: "GET", statusCode: httpResponse.statusCode,
                     response: responseBody, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
    // MARK: - DayState / Coach / Conflict (AMA-1150)

    /// Fetch today's DayState from the planning API
    func fetchDayState() async throws -> DayStateResponse {
        let url = URL(string: "\(baseURL)/api/v1/planning/day-state")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try Self.makeDecoder().decode(DayStateResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/api/v1/planning/day-state", method: "GET",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Ask the AI coach a quick question
    func askCoach(question: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/v1/coach/quick")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.httpBody = try JSONEncoder().encode(["question": question])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let result = try Self.makeDecoder().decode(CoachQuickResponse.self, from: data)
            return result.answer
        case 401:
            throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/api/v1/coach/quick", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Resolve a training conflict (adjust or keep)
    func resolveConflict(action: String, message: String) async throws {
        let url = URL(string: "\(baseURL)/api/v1/planning/resolve-conflict")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.httpBody = try JSONEncoder().encode(["action": action, "message": message])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/api/v1/planning/resolve-conflict", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Planning API (AMA-1147 / AMA-1133)

    func fetchDayStates(from: String, to: String) async throws -> [DayState] {
        let url = URL(string: "\(baseURL)/api/v1/planning/day-states?from=\(from)&to=\(to)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200:
            return try Self.makeDecoder().decode([DayState].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func generateWeek(request genRequest: GenerateWeekRequest? = nil) async throws -> ProposedPlan {
        let url = URL(string: "\(baseURL)/api/v1/planning/generate-week")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let genRequest = genRequest {
            request.httpBody = try JSONEncoder().encode(genRequest)
        } else {
            request.httpBody = "{}".data(using: .utf8)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(ProposedPlan.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict] {
        let url = URL(string: "\(baseURL)/api/v1/planning/conflicts?start_date=\(startDate)&end_date=\(endDate)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode([Conflict].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func parseWorkoutText(text: String, context: String? = nil) async throws -> ParsedWorkout {
        let url = URL(string: "\(baseURL)/api/v1/planning/parse-workout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ParseWorkoutRequest(text: text, context: context))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(ParsedWorkout.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Actions API (AMA-1147 / AMA-1133)

    func fetchPendingActions() async throws -> [PendingAction] {
        let url = URL(string: "\(baseURL)/api/v1/actions/pending")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode([PendingAction].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func respondToAction(id: String, response actionResponse: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/api/v1/actions/\(id)/respond")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["response": actionResponse])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(ActionResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Coach API (AMA-1147 / AMA-1133)

    func sendCoachMessage(message: String, context: CoachContext? = nil) async throws -> CoachResponse {
        let chatURL = AppEnvironment.current.chatAPIURL
        let url = URL(string: "\(chatURL)/api/v1/coach/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CoachMessageRequest(message: message, context: context))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(CoachResponse.self, from: data)
        case 401: throw APIError.unauthorized
        case 429:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverErrorWithBody(429, body)
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func getFatigueAdvice(fatigueScore: Double? = nil, loadHistory: [DailyLoad]? = nil) async throws -> FatigueAdvice {
        let chatURL = AppEnvironment.current.chatAPIURL
        let url = URL(string: "\(chatURL)/api/v1/coach/fatigue-advice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(FatigueAdviceRequest(currentFatigueScore: fatigueScore, recentLoadHistory: loadHistory))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(FatigueAdvice.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func fetchCoachMemories() async throws -> [CoachMemory] {
        let chatURL = AppEnvironment.current.chatAPIURL
        let url = URL(string: "\(chatURL)/api/v1/coach/memories")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode([CoachMemory].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Analytics API (AMA-1147 / AMA-1133)

    func fetchShoeComparison() async throws -> [ShoeStats] {
        let url = URL(string: "\(baseURL)/api/v1/analytics/shoes")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode([ShoeStats].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Billing API (AMA-1147 / AMA-1133)

    func fetchSubscription() async throws -> Subscription {
        let url = URL(string: "\(baseURL)/api/v1/billing/subscription")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(Subscription.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Notification Preferences API (AMA-1147 / AMA-1133)

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        let url = URL(string: "\(baseURL)/api/v1/preferences/notifications")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(NotificationPreferences.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences {
        let url = URL(string: "\(baseURL)/api/v1/preferences/notifications")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = authHeaders
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(prefs)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(NotificationPreferences.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - XP + Level (AMA-1285)

    func fetchXP() async throws -> XPData {
        let url = URL(string: "\(AppEnvironment.current.chatAPIURL)/gamification/xp")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = Self.makeDecoder()
        return try decoder.decode(XPData.self, from: data)
    }
}

// MARK: - DayState API Response Models (AMA-1150)

struct DayStateResponse: Codable {
    let date: String
    let readinessScore: Int
    let readinessLabel: String
    let sessions: [DayStateSessionResponse]
    let conflictAlert: DayStateConflictResponse?
}

struct DayStateSessionResponse: Codable {
    let id: String
    let name: String
    let scheduledTime: String?
    let sport: String
    let durationMinutes: Int?
    let isCompleted: Bool
    let isNext: Bool
}

struct DayStateConflictResponse: Codable {
    let message: String
    let severity: String
    let suggestedAction: String?
}

struct CoachQuickResponse: Codable {
    let answer: String
}

// MARK: - Completion History Responses

private struct CompletionsListResponse: Codable {
    let success: Bool
    let completions: [WorkoutCompletion]
}

private struct CompletionDetailWrappedResponse: Codable {
    let success: Bool
    let completion: WorkoutCompletionDetail
}

// MARK: - Profile Response
struct ProfileResponse: Codable {
    let success: Bool
    let profile: UserProfile
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

// MARK: - Instagram Reel Ingestion Response (AMA-564)

struct IngestInstagramReelResponse: Codable {
    let title: String?
    let workoutType: String?
    let source: String?
}

// MARK: - Text Ingestion Response

struct IngestTextResponse: Codable {
    let name: String?
    let sport: String?
    let source: String?
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

// MARK: - Social Feed (AMA-1273)

extension APIService {
    func fetchSocialFeed(cursor: String?, limit: Int) async throws -> FeedResponse {
        var urlString = "\(baseURL)/social/feed?limit=\(limit)"
        if let cursor = cursor {
            urlString += "&cursor=\(cursor)"
        }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(FeedResponse.self, from: data)
    }

    func addSocialReaction(postId: String, emoji: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/posts/\(postId)/react") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.httpBody = try JSONEncoder().encode(["emoji": emoji])
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func removeSocialReaction(postId: String, emoji: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/posts/\(postId)/react/\(emoji)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = authHeaders
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func fetchSocialComments(postId: String) async throws -> CommentsResponse {
        guard let url = URL(string: "\(baseURL)/social/posts/\(postId)/comments") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(CommentsResponse.self, from: data)
    }

    func postSocialComment(postId: String, text: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/posts/\(postId)/comment") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        request.httpBody = try JSONEncoder().encode(["text": text])
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func fetchSocialSettings() async throws -> SocialSettings {
        guard let url = URL(string: "\(baseURL)/social/settings") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(SocialSettings.self, from: data)
    }

    func updateSocialSettings(_ settings: SocialSettings) async throws {
        guard let url = URL(string: "\(baseURL)/social/settings") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = authHeaders
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(settings)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func fetchUserPublicProfile(userId: String) async throws -> UserPublicProfile {
        guard let url = URL(string: "\(baseURL)/social/users/\(userId)/profile") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(UserPublicProfile.self, from: data)
    }

    // MARK: - Challenges (AMA-1276)

    func fetchChallenges() async throws -> ChallengesResponse {
        guard let url = URL(string: "\(baseURL)/social/challenges") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(ChallengesResponse.self, from: data)
    }

    func fetchChallengeDetail(id: String) async throws -> ChallengeDetailResponse {
        guard let url = URL(string: "\(baseURL)/social/challenges/\(id)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(ChallengeDetailResponse.self, from: data)
    }

    func createChallenge(_ request: CreateChallengeRequest) async throws {
        guard let url = URL(string: "\(baseURL)/social/challenges") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func joinChallenge(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/challenges/\(id)/join") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - Training Crews (AMA-1277)

    func fetchMyCrews() async throws -> CrewListResponse {
        guard let url = URL(string: "\(baseURL)/social/crews") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(CrewListResponse.self, from: data)
    }

    func fetchCrewDetail(id: String) async throws -> CrewDetail {
        guard let url = URL(string: "\(baseURL)/social/crews/\(id)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(CrewDetail.self, from: data)
    }

    func fetchCrewFeed(crewId: String) async throws -> CrewFeedResponse {
        guard let url = URL(string: "\(baseURL)/social/crews/\(crewId)/feed") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(CrewFeedResponse.self, from: data)
    }

    func createCrew(_ request: CreateCrewRequest) async throws {
        guard let url = URL(string: "\(baseURL)/social/crews") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func joinCrew(crewId: String, request: JoinCrewRequest) async throws {
        guard let url = URL(string: "\(baseURL)/social/crews/\(crewId)/join") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func leaveCrew(crewId: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/crews/\(crewId)/leave") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.allHTTPHeaderFields = authHeaders
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - Workout Editor (AMA-1231)

    /// Save a new or edited workout
    func saveWorkout(_ request: WorkoutSaveRequest) async throws -> Workout {
        guard let url = URL(string: "\(baseURL)/workouts/save") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders
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
        guard let url = URL(string: "\(baseURL)/workouts/\(workoutId)/export/fit") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    /// Export workout as CSV data
    func exportWorkoutCSV(workoutId: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/workouts/\(workoutId)/export/csv") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    // MARK: - Training Programs (AMA-1231)

    func fetchPrograms(status: String) async throws -> ProgramsResponse {
        guard let url = URL(string: "\(baseURL)/programs?status=\(status)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(httpResponse.statusCode)
        }
        return try APIService.makeDecoder().decode(ProgramsResponse.self, from: data)
    }

    func fetchProgramDetail(id: String) async throws -> TrainingProgram {
        guard let url = URL(string: "\(baseURL)/programs/\(id)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(httpResponse.statusCode)
        }
        return try APIService.makeDecoder().decode(TrainingProgram.self, from: data)
    }

    // MARK: - Calendar Sync (AMA-1238)

    func fetchConnectedCalendars() async throws -> [ConnectedCalendar] {
        let calURL = AppEnvironment.current.calendarAPIURL
        guard let url = URL(string: "\(calURL)/calendars/connected") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode([ConnectedCalendar].self, from: data)
    }

    func connectCalendar(provider: String) async throws -> String {
        let calURL = AppEnvironment.current.calendarAPIURL
        guard let url = URL(string: "\(calURL)/calendars/connect") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        let body = ["provider": provider]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct ConnectResponse: Codable { let url: String }
        let result = try APIService.makeDecoder().decode(ConnectResponse.self, from: data)
        return result.url
    }

    func syncCalendar(calendarId: String) async throws -> CalendarSyncResponse {
        let calURL = AppEnvironment.current.calendarAPIURL
        guard let url = URL(string: "\(calURL)/calendars/\(calendarId)/sync") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct SyncAPIResponse: Codable { let syncedEvents: Int? }
        let result = try APIService.makeDecoder().decode(SyncAPIResponse.self, from: data)
        return CalendarSyncResponse(syncedEvents: result.syncedEvents)
    }

    func disconnectCalendar(calendarId: String) async throws {
        let calURL = AppEnvironment.current.calendarAPIURL
        guard let url = URL(string: "\(calURL)/calendars/\(calendarId)/disconnect") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = authHeaders
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
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
