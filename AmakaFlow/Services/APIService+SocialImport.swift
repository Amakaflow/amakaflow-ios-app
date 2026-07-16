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
    /// Apify + LLM reel ingest often exceeds 15s; align with ingestor smoke (90s) plus headroom.
    private static let socialURLIngestTimeoutInterval: TimeInterval = 120
    private static let socialSaveTimeoutInterval: TimeInterval = 30

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

    /// POST /workouts/save body for mapper-api (`workout_data` + `sources` + `device`).
    static func mapperSaveBody(from request: WorkoutSaveRequest, source: String) throws -> [String: Any] {
        let blockPayload: [[String: Any]]
        if let blocks = request.blocks, !blocks.isEmpty {
            blockPayload = blocks.map { block in
                var object: [String: Any] = [
                    "exercises": block.exercises.map { provenanceExercise(from: $0) }
                ]
                if let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    object["label"] = label
                }
                if block.rounds > 1 {
                    object["rounds"] = block.rounds
                }
                return object
            }
        } else {
            let exercises = request.intervals.compactMap { provenanceExercise(from: $0) }
            guard !exercises.isEmpty else {
                throw APIError.serverErrorWithBody(
                    422,
                    "Add at least one exercise before saving — import didn't extract a usable list."
                )
            }
            blockPayload = [["label": "Main", "exercises": exercises]]
        }

        var workoutData: [String: Any] = [
            "title": request.name,
            "workout_type": request.sport,
            "blocks": blockPayload
        ]
        if let description = request.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            workoutData["description"] = description
        }
        var metadata: [String: Any] = [:]
        if let sourceUrl = request.sourceUrl {
            metadata["source_url"] = sourceUrl
        }
        if let creator = request.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines), !creator.isEmpty {
            metadata["creator"] = creator
        }
        if !metadata.isEmpty {
            workoutData["metadata"] = metadata
        }
        return [
            "workout_data": workoutData,
            "sources": [source],
            "device": "ios",
            "title": request.name
        ]
    }

    private static func provenanceExercise(from exercise: SocialImportExercise) -> [String: Any] {
        var object: [String: Any] = [
            "name": exercise.name,
            "sets": exercise.sets ?? 3,
            "reps": exercise.reps ?? 10
        ]
        if let loadText = exercise.load?.trimmingCharacters(in: .whitespacesAndNewlines), !loadText.isEmpty {
            let parsed = Workout.resolveLegacyLoadAndInstruction(from: loadText)
            if let parsedLoad = parsed.load, parsedLoad.value > 0 {
                object["weight"] = parsedLoad.value
                object["weight_unit"] = parsedLoad.unit
            } else {
                object["notes"] = loadText
            }
        } else if let notes = exercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !notes.isEmpty,
                  !Exercise.looksLikeMuscleFocus(notes) {
            object["notes"] = notes
        }
        if let focus = exercise.focus?.trimmingCharacters(in: .whitespacesAndNewlines), !focus.isEmpty {
            object["muscle_group"] = focus
        }
        if let seconds = exercise.seconds, seconds > 0 {
            object["duration_sec"] = seconds
        }
        return object
    }

    private static func provenanceExercise(from interval: WorkoutSaveInterval) -> [String: Any]? {
        switch interval.type {
        case "reps":
            let name = (interval.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var exercise: [String: Any] = [
                "name": name,
                "sets": interval.sets ?? 3,
                "reps": interval.reps ?? 10
            ]
            if let load = interval.load?.trimmingCharacters(in: .whitespacesAndNewlines), !load.isEmpty {
                exercise["notes"] = load
            }
            return exercise
        case "time", "warmup", "cooldown":
            let name = (interval.target ?? interval.name ?? "Exercise")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var exercise: [String: Any] = ["name": name]
            if let seconds = interval.seconds { exercise["duration_sec"] = seconds }
            return exercise
        case "distance":
            let name = (interval.target ?? interval.name ?? "Exercise")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var exercise: [String: Any] = ["name": name, "reps": "\(interval.meters ?? 0)m"]
            return exercise
        case "rest":
            return nil
        default:
            return nil
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

        if let blocks = request.blocks, !blocks.isEmpty {
            let mappedBlocks = blocks.map { block in
                Block(
                    label: block.label,
                    structure: .straight,
                    rounds: max(1, block.rounds),
                    exercises: block.exercises.map { $0.toExercise() }
                )
            }
            return Workout(
                id: workoutId,
                name: request.name,
                sport: WorkoutSport(rawValue: request.sport) ?? .strength,
                duration: max(mappedBlocks.flatMap(\.exercises).count * 180, 600),
                blocks: mappedBlocks,
                description: request.description,
                source: WorkoutSource(rawValue: source) ?? .other,
                sourceUrl: request.sourceUrl,
                creatorName: request.creatorName
            )
        }

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
            description: request.description,
            source: WorkoutSource(rawValue: source) ?? .other,
            sourceUrl: request.sourceUrl,
            creatorName: request.creatorName
        )
    }
}
