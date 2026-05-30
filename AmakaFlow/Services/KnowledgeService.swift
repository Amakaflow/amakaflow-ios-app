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
    case unauthorized
    case httpError(Int, String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Authentication required"
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

    /// AMA-1827: route through mobile-bff (`/v1/knowledge/*`) instead of
    /// chat-api directly. Backend chat-api can be renamed without an iOS
    /// release. See AMA-1817 epic.
    private var baseURL: String { "\(AppEnvironment.current.mobileBFFURL)/v1" }
    private let session = URLSession.shared

    private init() {}

    // MARK: - Auth Headers

    private func authHeaders() async throws -> [String: String] {
        var headers = ["Content-Type": "application/json"]
        guard let token = try await AuthViewModel.shared.token() else {
            throw KnowledgeServiceError.unauthorized
        }
        headers["Authorization"] = "Bearer \(token)"
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
        request.allHTTPHeaderFields = try await authHeaders()

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
        request.allHTTPHeaderFields = try await authHeaders()

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
    /// Provide either `url` or `text`; AddToLibrary passes kind/tags as metadata
    /// because chat-api's IngestRequest has no first-class `kind` or `tags` write
    /// field yet. Library list remains honest and only displays what GET returns.
    func ingest(
        url: String? = nil,
        text: String? = nil,
        kind: Components.Schemas.LibraryKind? = nil,
        tags: [String] = [],
        preview: OGPreview? = nil
    ) async throws -> KnowledgeCard {
        guard url != nil || text != nil else {
            throw KnowledgeServiceError.invalidURL
        }

        guard let endpoint = URL(string: "\(baseURL)/knowledge/cards") else {
            throw KnowledgeServiceError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await authHeaders()

        var body: [String: Any] = [:]
        if let url {
            body["source_url"] = url
            body["source_type"] = Self.sourceType(for: URL(string: url), requestedKind: kind)
        } else if let text {
            body["raw_content"] = text
            body["source_type"] = "manual"
        }
        if let previewTitle = preview?.title, !previewTitle.isEmpty {
            body["title"] = previewTitle
        }

        var metadata: [String: Any] = [:]
        if let kind {
            metadata["requested_library_kind"] = kind.rawValue
        }
        if !tags.isEmpty {
            metadata["requested_tags"] = tags
            // TODO(AMA-2006): backend gap — chat-api IngestRequest does not persist
            // caller-provided tags on POST /v1/knowledge/cards yet. Keep this intent
            // explicit; Library reload will only show tags if the backend returns them.
            body["tags"] = tags
        }
        if let siteName = preview?.siteName {
            metadata["og_site_name"] = siteName
        }
        if let image = preview?.imageURL?.absoluteString {
            metadata["og_image"] = image
        }
        if !metadata.isEmpty {
            body["metadata"] = metadata
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

    private static func sourceType(
        for url: URL?,
        requestedKind: Components.Schemas.LibraryKind?
    ) -> String {
        let host = (url?.host ?? "").lowercased()
        switch requestedKind {
        case .video:
            if host.contains("youtube") || host.contains("youtu.be") {
                return "youtube"
            }
            return "social_media"
        case .workout:
            return "workout_log"
        case .article, .none:
            return "url"
        case .plan:
            // TODO(AMA-2006): backend gap — LibraryKind.plan has no persisted
            // knowledge source_type mapping. Save as URL and preserve the requested
            // kind in metadata instead of pretending the list will return `plan`.
            return "url"
        }
    }

    /// Delete a knowledge card by ID. The API returns 204 No Content on success.
    func deleteCard(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/knowledge/cards/\(id)") else {
            throw KnowledgeServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = try await authHeaders()

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
