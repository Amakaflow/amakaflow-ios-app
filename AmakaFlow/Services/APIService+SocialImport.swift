//
//  APIService+SocialImport.swift
//  AmakaFlow
//
//  AMA-2285: social URL / text / image ingest helpers (no scraping).
//

import Foundation

/// Narrow API surface for social → Library import (AMA-2285). No scraping — official ingest only.
protocol SocialImportAPIProviding {
    /// Ingest a social / web URL; returns raw JSON for SocialImportDraft parsing.
    func ingestSocialURL(url: String, platform: SocialImportPlatform) async throws -> Data

    /// Ingest pasted plain text; returns raw JSON for SocialImportDraft parsing.
    func ingestSocialText(text: String, source: String?) async throws -> Data

    /// Ingest a screenshot / photo; returns raw JSON for SocialImportDraft parsing.
    func ingestSocialImage(imageData: Data, filename: String) async throws -> Data

    /// Read coaching equipment for import adaptation (honest empty when missing).
    func socialImportEquipmentContext() async -> (empty: Bool, note: String?)

    /// AMA-2305 / ADR-017 — BFF structure suggestions after social parse.
    func suggestStructure(text: String, source: String?) async throws -> StructureSuggestResult

    /// AMA-2305 — apply Describe note / ops (live BFF, not a stub).
    func applyStructure(_ request: ApplyStructureRequest) async throws -> ApplyStructureResult
}

extension APIService {
    /// Apify + LLM reel ingest often exceeds 15s; align with ingestor smoke (90s) plus headroom.
    private static let socialURLIngestTimeoutInterval: TimeInterval = 120
    /// Short per-request timeouts for async start + poll (docs#46) — survives app backgrounding.
    private static let socialAsyncStartTimeoutInterval: TimeInterval = 30
    private static let socialAsyncPollTimeoutInterval: TimeInterval = 15
    private static let socialAsyncPollIntervalNanoseconds: UInt64 = 1_500_000_000
    private static let socialAsyncPollDeadlineSeconds: TimeInterval = 180
    private static let socialSaveTimeoutInterval: TimeInterval = 30

    // MARK: - Social Import (AMA-2285)

    /// POST /ingest/{platform.ingestPath} with a URL. Returns raw JSON for draft parsing.
    /// Instagram uses async start + poll (docs#46) so leaving the app does not drop a 120s POST.
    func ingestSocialURL(url: String, platform: SocialImportPlatform) async throws -> Data {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        if platform == .instagram {
            return try await ingestInstagramReelAsync(url: url)
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let path = platform.ingestPath
        guard let requestURL = URL(string: "\(ingestorURL)/ingest/\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.socialURLIngestTimeoutInterval
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": url])

        print("[APIService] ingestSocialURL - \(requestURL.absoluteString)")

        let (data, response) = try await session.data(for: request)
        return try await Self.validateSocialIngestResponse(
            data: data,
            response: response,
            endpoint: "/ingest/\(path)"
        )
    }

    /// docs#46 — POST /ingest/instagram_reel/async then poll GET /tasks/{id}/status.
    private func ingestInstagramReelAsync(url: String) async throws -> Data {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        guard let startURL = URL(string: "\(ingestorURL)/ingest/instagram_reel/async") else {
            throw APIError.invalidURL
        }

        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.timeoutInterval = Self.socialAsyncStartTimeoutInterval
        startRequest.allHTTPHeaderFields = try await makeAuthHeaders()
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: ["url": url])

        print("[APIService] ingestInstagramReelAsync - \(startURL.absoluteString)")

        let (startData, startResponse) = try await session.data(for: startRequest)
        _ = try await Self.validateSocialIngestResponse(
            data: startData,
            response: startResponse,
            endpoint: "/ingest/instagram_reel/async"
        )

        guard
            let startJSON = try JSONSerialization.jsonObject(with: startData) as? [String: Any],
            let taskId = startJSON["task_id"] as? String,
            !taskId.isEmpty
        else {
            throw APIError.invalidResponse
        }

        let deadline = Date().addingTimeInterval(Self.socialAsyncPollDeadlineSeconds)
        while Date() < deadline {
            if Task.isCancelled { throw CancellationError() }

            guard let statusURL = URL(string: "\(ingestorURL)/tasks/\(taskId)/status") else {
                throw APIError.invalidURL
            }
            var statusRequest = URLRequest(url: statusURL)
            statusRequest.httpMethod = "GET"
            statusRequest.timeoutInterval = Self.socialAsyncPollTimeoutInterval
            statusRequest.allHTTPHeaderFields = try await makeAuthHeaders()

            let (statusData, statusResponse) = try await session.data(for: statusRequest)
            guard let http = statusResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.serverError(http.statusCode)
            }

            guard
                let statusJSON = try JSONSerialization.jsonObject(with: statusData) as? [String: Any],
                let status = statusJSON["status"] as? String
            else {
                throw APIError.invalidResponse
            }

            switch status {
            case "completed":
                if let workout = statusJSON["result"] as? [String: Any],
                   let nested = workout["workout"] as? [String: Any] {
                    return try JSONSerialization.data(withJSONObject: nested)
                }
                if let result = statusJSON["result"] as? [String: Any] {
                    // Some paths may return the workout dict directly
                    if result["blocks"] != nil || result["title"] != nil {
                        return try JSONSerialization.data(withJSONObject: result)
                    }
                    if let nested = result["workout"] as? [String: Any] {
                        return try JSONSerialization.data(withJSONObject: nested)
                    }
                }
                throw APIError.invalidResponse
            case "failed":
                let message = (statusJSON["error"] as? String)
                    ?? "Instagram reel import failed"
                throw APIError.serverErrorWithBody(400, message)
            case "queued", "processing":
                try await Task.sleep(nanoseconds: Self.socialAsyncPollIntervalNanoseconds)
            default:
                try await Task.sleep(nanoseconds: Self.socialAsyncPollIntervalNanoseconds)
            }
        }

        throw APIError.serverErrorWithBody(
            504,
            "Import is still running — open the app again in a minute, or retry."
        )
    }

    /// POST /ingest/text for pasted captions / notes. Returns raw JSON.
    func ingestSocialText(text: String, source: String? = nil) async throws -> Data {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        guard let requestURL = URL(string: "\(ingestorURL)/ingest/text") else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        var headers = try await makeAuthHeaders()
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        request.allHTTPHeaderFields = headers

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"text\"\r\n\r\n".utf8))
        body.append(Data("\(text)\r\n".utf8))
        if let source = source {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"source\"\r\n\r\n".utf8))
            body.append(Data("\(source)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body

        print("[APIService] ingestSocialText - \(requestURL.absoluteString)")

        let (data, response) = try await session.data(for: request)
        return try await Self.validateSocialIngestResponse(
            data: data,
            response: response,
            endpoint: "/ingest/text"
        )
    }

    /// POST /ingest/image with multipart image bytes. Returns raw JSON.
    func ingestSocialImage(imageData: Data, filename: String = "workout.jpg") async throws -> Data {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        guard let requestURL = URL(string: "\(ingestorURL)/ingest/image") else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        var headers = try await makeAuthHeaders()
        headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        request.allHTTPHeaderFields = headers

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body

        print("[APIService] ingestSocialImage - \(requestURL.absoluteString)")

        let (data, response) = try await session.data(for: request)
        return try await Self.validateSocialIngestResponse(
            data: data,
            response: response,
            endpoint: "/ingest/image"
        )
    }

    /// Equipment adaptation note for social import. Honest empty + continue when missing.
    func socialImportEquipmentContext() async -> (empty: Bool, note: String?) {
        do {
            guard let profile = try await getCoachingProfile(),
                  let inventory = profile.equipment else {
                return (true, "No equipment profile yet — you can still import and edit.")
            }
            let names = Self.equipmentNames(from: inventory)
            if names.isEmpty {
                return (true, "Equipment list is empty — continuing; set equipment in Profile anytime.")
            }
            let preview = names.prefix(6).joined(separator: ", ")
            let suffix = names.count > 6 ? "…" : ""
            return (false, "Using your equipment: \(preview)\(suffix)")
        } catch {
            return (true, "Couldn't load equipment — continuing without adaptation.")
        }
    }

    private static func validateSocialIngestResponse(
        data: Data,
        response: URLResponse,
        endpoint: String
    ) async throws -> Data {
        let responseString = String(data: data, encoding: .utf8)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[APIService] \(endpoint) - Status: \(httpResponse.statusCode)")

        if httpResponse.statusCode >= 400 {
            await DebugLogService.shared.logAPIError(
                endpoint: endpoint,
                method: "POST",
                statusCode: httpResponse.statusCode,
                response: responseString
            )
        }

        switch httpResponse.statusCode {
        case 200, 201:
            return data
        case 400:
            throw APIError.serverErrorWithBody(400, responseString ?? "Bad request")
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.serverErrorWithBody(403, responseString ?? "Forbidden")
        case 422:
            throw APIError.serverErrorWithBody(422, responseString ?? "Could not parse workout")
        default:
            if (400..<500).contains(httpResponse.statusCode) {
                throw APIError.serverErrorWithBody(
                    httpResponse.statusCode,
                    responseString ?? "Request failed"
                )
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    private static func equipmentNames(from inventory: Components.Schemas.EquipmentInventory) -> [String] {
        var names: [String] = []
        if let strength = inventory.strength?.additionalProperties {
            names.append(contentsOf: strength.filter(\.value).map(\.key))
        }
        if let cardio = inventory.cardio?.additionalProperties {
            names.append(contentsOf: cardio.filter(\.value).map(\.key))
        }
        if let mobility = inventory.mobility?.additionalProperties {
            names.append(contentsOf: mobility.filter(\.value).map(\.key))
        }
        if let bodyweight = inventory.bodyweight?.additionalProperties {
            names.append(contentsOf: bodyweight.filter(\.value).map(\.key))
        }
        return names.sorted()
    }

    // MARK: - Provenance-aware workout save (AMA-2285)

    /// Mapper-compatible save when `source` is set (`sources` + `device`).
    /// After save, pushes to iOS Companion so `/workouts/incoming` (Library) can see it.
    func saveWorkoutWithProvenance(_ request: WorkoutSaveRequest, source: String) async throws -> Workout {
        guard let url = URL(string: "\(baseURL)/workouts/save") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.socialSaveTimeoutInterval
        req.allHTTPHeaderFields = try await makeAuthHeaders()

        let body = try Self.mapperSaveBody(from: request, source: source)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let responseString = String(data: data, encoding: .utf8)
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseString ?? "Save failed")
        }

        let workout = try Self.parseProvenanceSaveResponse(
            data: data,
            request: request,
            source: source
        )
        try await pushSavedWorkoutToIOSCompanion(workoutId: workout.id)
        return workout
    }

    /// Marks a saved workout visible to Library via GET /workouts/incoming (ios_companion_synced_at).
    private func pushSavedWorkoutToIOSCompanion(workoutId: String) async throws {
        let encodedID = try Self.pathSegment(workoutId)
        guard let url = URL(string: "\(baseURL)/workouts/\(encodedID)/push/ios-companion") else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.socialSaveTimeoutInterval
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [String: String]())

        print("[APIService] pushSavedWorkoutToIOSCompanion - \(url.absoluteString)")

        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let responseString = String(data: data, encoding: .utf8)
            throw APIError.serverErrorWithBody(
                httpResponse.statusCode,
                responseString ?? "Saved workout but couldn't add it to Library."
            )
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = object["success"] as? Bool,
           !success {
            let message = object["message"] as? String ?? "Saved workout but couldn't add it to Library."
            throw APIError.serverErrorWithBody(500, message)
        }
    }

    private static func parseProvenanceSaveResponse(
        data: Data,
        request: WorkoutSaveRequest,
        source: String
    ) throws -> Workout {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = object["success"] as? Bool,
           !success {
            let message = object["message"] as? String ?? "Save failed"
            throw APIError.serverErrorWithBody(500, message)
        }

        if let decoded = try? APIService.makeDecoder().decode(Workout.self, from: data) {
            let resolvedSource = decoded.source == .other || decoded.source.rawValue.isEmpty
                ? (WorkoutSource(rawValue: source) ?? .other)
                : decoded.source
            return Workout(
                id: decoded.id,
                name: decoded.name,
                sport: decoded.sport,
                duration: decoded.duration,
                blocks: decoded.blocks,
                description: decoded.description ?? request.description,
                source: resolvedSource,
                sourceUrl: request.sourceUrl ?? decoded.sourceUrl,
                creatorName: decoded.creatorName ?? request.creatorName,
                createdAt: decoded.createdAt
            )
        }

        return synthesizedProvenanceWorkout(from: request, source: source, responseData: data)
    }
}
