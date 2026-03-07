//
//  KnowledgeService.swift
//  AmakaFlow
//
//  API client for the Knowledge Base endpoints served by chat-api (port 8005).
//

import Foundation
import Combine

// MARK: - Models

struct KnowledgeCard: Identifiable, Codable {
    let id: String
    let title: String?
    let summary: String?
    let microSummary: String?
    let keyTakeaways: [String]
    let sourceType: String
    let sourceUrl: String?
    let processingStatus: String
    let tags: [String]
    let visibility: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case microSummary = "micro_summary"
        case keyTakeaways = "key_takeaways"
        case sourceType = "source_type"
        case sourceUrl = "source_url"
        case processingStatus = "processing_status"
        case tags
        case visibility
        case createdAt = "created_at"
    }
}

struct KnowledgeCardListResponse: Codable {
    let items: [KnowledgeCard]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - Errors

enum KnowledgeServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Service

@MainActor
class KnowledgeService: ObservableObject {
    static let shared = KnowledgeService()

    private var baseURL: String { AppEnvironment.current.chatAPIURL }
    private let session = URLSession.shared

    private init() {}

    // MARK: - Auth Headers

    private var authHeaders: [String: String] {
        var headers = ["Content-Type": "application/json"]

        // E2E Test mode: Use X-Test-Auth header bypass instead of JWT
        #if DEBUG
        if let testAuthSecret = TestAuthStore.shared.authSecret,
           let testUserId = TestAuthStore.shared.userId,
           !testAuthSecret.isEmpty {
            headers["X-Test-Auth"] = testAuthSecret
            headers["X-Test-User-Id"] = testUserId
            print("[KnowledgeService] Using X-Test-Auth header bypass for E2E tests")
            return headers
        }
        #endif

        // Normal auth: Use JWT token
        if let token = PairingService.shared.getToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    // MARK: - API Methods

    /// Fetch a paginated list of knowledge cards for the current user.
    func listCards(limit: Int = 20, offset: Int = 0) async throws -> KnowledgeCardListResponse {
        guard let url = URL(string: "\(baseURL)/knowledge/cards?limit=\(limit)&offset=\(offset)") else {
            throw KnowledgeServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        print("[KnowledgeService] listCards - URL: \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw KnowledgeServiceError.httpError(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(KnowledgeCardListResponse.self, from: data)
        } catch {
            throw KnowledgeServiceError.decodingError(error)
        }
    }

    /// Search knowledge cards by query string.
    func searchCards(query: String, limit: Int = 20) async throws -> KnowledgeCardListResponse {
        var components = URLComponents(string: "\(baseURL)/knowledge/cards/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components?.url else {
            throw KnowledgeServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = authHeaders

        print("[KnowledgeService] searchCards - URL: \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw KnowledgeServiceError.httpError(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(KnowledgeCardListResponse.self, from: data)
        } catch {
            throw KnowledgeServiceError.decodingError(error)
        }
    }

    /// Ingest a new knowledge card from a URL or raw text.
    /// Provide either `url` or `text`; `sourceType` is inferred automatically.
    func ingest(url: String? = nil, text: String? = nil) async throws -> KnowledgeCard {
        guard url != nil || text != nil else {
            throw KnowledgeServiceError.invalidURL
        }

        guard let endpoint = URL(string: "\(baseURL)/knowledge/cards") else {
            throw KnowledgeServiceError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = authHeaders

        var body: [String: String] = [:]
        if let url {
            body["source_url"] = url
            body["source_type"] = "url"
        } else if let text {
            body["text"] = text
            body["source_type"] = "manual"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[KnowledgeService] ingest - URL: \(endpoint.absoluteString), sourceType: \(body["source_type"] ?? "unknown")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8)
            throw KnowledgeServiceError.httpError(httpResponse.statusCode, responseBody)
        }

        do {
            return try JSONDecoder().decode(KnowledgeCard.self, from: data)
        } catch {
            throw KnowledgeServiceError.decodingError(error)
        }
    }

    /// Delete a knowledge card by ID. The API returns 204 No Content on success.
    func deleteCard(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/knowledge/cards/\(id)") else {
            throw KnowledgeServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = authHeaders

        print("[KnowledgeService] deleteCard - id: \(id), URL: \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw KnowledgeServiceError.httpError(httpResponse.statusCode, body)
        }
        // 204 No Content — nothing to decode
    }
}
