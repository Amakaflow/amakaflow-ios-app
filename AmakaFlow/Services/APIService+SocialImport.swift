//
//  APIService+SocialImport.swift
//  AmakaFlow
//
//  AMA-2285: social URL / text / image ingest helpers (no scraping).
//

import Foundation

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
}
