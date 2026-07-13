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
}

extension APIService {
    // MARK: - Social Import (AMA-2285)

    /// POST /ingest/{platform.ingestPath} with a URL. Returns raw JSON for draft parsing.
    func ingestSocialURL(url: String, platform: SocialImportPlatform) async throws -> Data {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let path = platform.ingestPath
        guard let requestURL = URL(string: "\(ingestorURL)/ingest/\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
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
        case 422:
            throw APIError.serverErrorWithBody(422, responseString ?? "Could not parse workout")
        default:
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
    func saveWorkoutWithProvenance(_ request: WorkoutSaveRequest, source: String) async throws -> Workout {
        guard let url = URL(string: "\(baseURL)/workouts/save") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.allHTTPHeaderFields = try await makeAuthHeaders()

        let intervalsPayload = Self.provenanceIntervalsPayload(from: request.intervals)
        var body: [String: Any] = [
            "name": request.name,
            "title": request.name,
            "sport": request.sport,
            "intervals": intervalsPayload,
            "sources": [source],
            "device": "ios"
        ]
        if let sourceUrl = request.sourceUrl {
            body["source_url"] = sourceUrl
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let responseString = String(data: data, encoding: .utf8)
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseString ?? "Save failed")
        }

        if let decoded = try? APIService.makeDecoder().decode(Workout.self, from: data) {
            if decoded.source == .other || decoded.source.rawValue.isEmpty {
                return Workout(
                    id: decoded.id,
                    name: decoded.name,
                    sport: decoded.sport,
                    duration: decoded.duration,
                    blocks: decoded.blocks,
                    description: decoded.description,
                    source: WorkoutSource(rawValue: source) ?? .other,
                    sourceUrl: request.sourceUrl ?? decoded.sourceUrl
                )
            }
            return decoded
        }

        return Self.synthesizedProvenanceWorkout(from: request, source: source, responseData: data)
    }

    private static func provenanceIntervalsPayload(from intervals: [WorkoutSaveInterval]) -> [[String: Any]] {
        intervals.map { interval in
            var item: [String: Any] = ["type": interval.type]
            if let name = interval.name { item["name"] = name }
            if let sets = interval.sets { item["sets"] = sets }
            if let reps = interval.reps { item["reps"] = reps }
            if let seconds = interval.seconds { item["seconds"] = seconds }
            if let meters = interval.meters { item["meters"] = meters }
            if let restSeconds = interval.restSeconds { item["rest_seconds"] = restSeconds }
            if let load = interval.load { item["load"] = load }
            if let target = interval.target { item["target"] = target }
            return item
        }
    }

    private static func synthesizedProvenanceWorkout(
        from request: WorkoutSaveRequest,
        source: String,
        responseData: Data
    ) -> Workout {
        let object = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
        let workoutId = (object?["workout_id"] as? String)
            ?? (object?["id"] as? String)
            ?? UUID().uuidString
        let intervals: [WorkoutInterval] = request.intervals.compactMap { interval in
            switch interval.type {
            case "time":
                return .time(seconds: interval.seconds ?? 60, target: interval.target ?? interval.name)
            case "reps":
                return .reps(
                    sets: interval.sets,
                    reps: interval.reps ?? 10,
                    name: interval.name ?? "Exercise",
                    load: interval.load,
                    restSec: interval.restSeconds,
                    followAlongUrl: nil
                )
            case "warmup":
                return .warmup(seconds: interval.seconds ?? 60, target: interval.target)
            case "cooldown":
                return .cooldown(seconds: interval.seconds ?? 60, target: interval.target)
            case "distance":
                return .distance(meters: interval.meters ?? 0, target: interval.target)
            case "rest":
                return .rest(seconds: interval.seconds)
            default:
                return nil
            }
        }
        return Workout(
            id: workoutId,
            name: request.name,
            sport: WorkoutSport(rawValue: request.sport) ?? .strength,
            duration: max(intervals.count * 180, 600),
            intervals: intervals,
            source: WorkoutSource(rawValue: source) ?? .other,
            sourceUrl: request.sourceUrl
        )
    }
}
