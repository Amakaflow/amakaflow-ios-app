//
//  IngestionAPIRepository.swift
//  AmakaFlow
//
//  AMA-1828: ingestor-API endpoints (voice parse, transcription,
//  personal-dictionary sync, Instagram reel + text ingestion, bulk
//  import) split out of APIService.swift. Implemented as
//  `extension APIService` so call sites and APIServiceProviding
//  conformance keep working unchanged.
//
//  All endpoints in this file route through
//  `AppEnvironment.current.ingestorAPIURL`.
//

import Foundation

extension APIService {

    // MARK: - Voice Workout Parsing (AMA-5)

    func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport? = nil) async throws -> VoiceWorkoutParseResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let url = URL(string: "\(ingestorURL)/workouts/parse-voice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()

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
            throw APIError.serverErrorWithBody(422, responseString ?? "Could not understand workout description")
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Instagram Reel Ingestion (AMA-564)

    func ingestInstagramReel(url: String) async throws -> IngestInstagramReelResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let requestURL = URL(string: "\(ingestorURL)/ingest/instagram_reel")!
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()

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

    func ingestText(text: String, source: String? = nil) async throws -> IngestTextResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let requestURL = URL(string: "\(ingestorURL)/ingest/text")!

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"

        var headers = try await makeAuthHeaders()
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        request.allHTTPHeaderFields = headers

        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"text\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(text)\r\n".data(using: .utf8)!)

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
        request.allHTTPHeaderFields = try await makeAuthHeaders()

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
        request.allHTTPHeaderFields = try await makeAuthHeaders()

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

    func fetchPersonalDictionary() async throws -> PersonalDictionaryResponse {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let url = URL(string: "\(ingestorURL)/voice/dictionary")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()

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

    // MARK: - Bulk Import (AMA-1415)

    func detectImport(request: BulkDetectRequest) async throws -> BulkDetectResponse {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        guard let url = URL(string: "\(ingestorURL)/import/detect") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        print("[APIService] detectImport - URL: \(url.absoluteString)")
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let responseString = String(data: data, encoding: .utf8)
        print("[APIService] detectImport - Status: \(httpResponse.statusCode)")
        switch httpResponse.statusCode {
        case 200, 201:
            return try APIService.makeDecoder().decode(BulkDetectResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            logError(endpoint: "/import/detect", method: "POST",
                     statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func matchExercises(request: BulkMatchRequest) async throws -> BulkMatchResponse {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        guard let url = URL(string: "\(ingestorURL)/import/match") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        print("[APIService] matchExercises - URL: \(url.absoluteString)")
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let responseString = String(data: data, encoding: .utf8)
        print("[APIService] matchExercises - Status: \(httpResponse.statusCode)")
        switch httpResponse.statusCode {
        case 200, 201:
            return try APIService.makeDecoder().decode(BulkMatchResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            logError(endpoint: "/import/match", method: "POST",
                     statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func previewImport(request: BulkPreviewRequest) async throws -> BulkPreviewResponse {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        guard let url = URL(string: "\(ingestorURL)/import/preview") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        print("[APIService] previewImport - URL: \(url.absoluteString)")
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let responseString = String(data: data, encoding: .utf8)
        print("[APIService] previewImport - Status: \(httpResponse.statusCode)")
        switch httpResponse.statusCode {
        case 200, 201:
            return try APIService.makeDecoder().decode(BulkPreviewResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            logError(endpoint: "/import/preview", method: "POST",
                     statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func executeImport(request: BulkExecuteRequest) async throws -> BulkExecuteResponse {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        guard let url = URL(string: "\(ingestorURL)/import/execute") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        print("[APIService] executeImport - URL: \(url.absoluteString)")
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let responseString = String(data: data, encoding: .utf8)
        print("[APIService] executeImport - Status: \(httpResponse.statusCode)")
        switch httpResponse.statusCode {
        case 200, 201, 202:
            return try APIService.makeDecoder().decode(BulkExecuteResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            logError(endpoint: "/import/execute", method: "POST",
                     statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func fetchImportStatus(jobId: String, profileId: String) async throws -> BulkImportStatus {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let encodedProfileId = profileId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profileId
        guard let url = URL(string: "\(ingestorURL)/import/status/\(jobId)?profile_id=\(encodedProfileId)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        print("[APIService] fetchImportStatus - URL: \(url.absoluteString)")
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let responseString = String(data: data, encoding: .utf8)
        print("[APIService] fetchImportStatus - Status: \(httpResponse.statusCode)")
        switch httpResponse.statusCode {
        case 200:
            return try APIService.makeDecoder().decode(BulkImportStatus.self, from: data)
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:
            logError(endpoint: "/import/status/\(jobId)", method: "GET",
                     statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func cancelImport(jobId: String, profileId: String) async throws {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let encodedProfileId = profileId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profileId
        guard let url = URL(string: "\(ingestorURL)/import/cancel/\(jobId)?profile_id=\(encodedProfileId)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        print("[APIService] cancelImport - URL: \(url.absoluteString)")
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200, 204: return
        case 401: throw APIError.unauthorized
        default:
            let responseString = String(data: data, encoding: .utf8)
            logError(endpoint: "/import/cancel/\(jobId)", method: "POST",
                     statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
