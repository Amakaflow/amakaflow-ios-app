//
//  URLImportService.swift
//  AmakaFlowShare
//
//  Handles posting URLs to the workout ingestor API via Background URLSession.
//  AMA-1257: iOS Share Extension — one-tap workout import from any app
//

import Foundation
import UserNotifications

/// Response from the /ingest/{source} endpoint
struct ShareIngestResponse: Codable {
    let title: String?
    let workoutType: String?
    let source: String?
    let needsClarification: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case workoutType = "workout_type"
        case source
        case needsClarification = "needs_clarification"
    }
}

/// Service that posts URLs to the workout ingestor backend.
final class URLImportService: NSObject {

    static let shared = URLImportService()

    private lazy var immediateSession: URLSession = {
        let config = URLSessionConfiguration.default
        // AMA-2285: fail fast — auth/parse/network should surface in ≤3s when possible.
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Import a single URL using an immediate (non-background) request.
    /// Returns the parsed response inline.
    func importURL(_ urlString: String, platform: DetectedPlatform) async throws -> ShareIngestResponse {
        let normalized = platform == .instagram
            ? PlatformDetector.normalizeInstagramURL(urlString)
            : urlString
        let request = try buildRequest(for: normalized, platform: platform)

        let (data, response) = try await immediateSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImportError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw ImportError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ImportError.serverError(httpResponse.statusCode, body)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ShareIngestResponse.self, from: data)
        } catch {
            throw ImportError.decodingFailed(error)
        }
    }

    // MARK: - Request Building

    private func buildRequest(for urlString: String, platform: DetectedPlatform) throws -> URLRequest {
        let env = SharedContainerManager.readEnvironment()
        let baseURL: String
        switch env {
        case "development": baseURL = "http://localhost:8004"
        case "production":  baseURL = "https://workout-ingestor-api.amakaflow.com"
        default:            baseURL = "https://workout-ingestor-api.staging.amakaflow.com"
        }

        let source = PlatformDetector.ingestSource(for: platform)
        guard let endpoint = URL(string: "\(baseURL)/ingest/\(source)") else {
            throw ImportError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Instagram reel ingest (Apify + LLM) exceeds 15s — align with main app (120s).
        request.timeoutInterval = platform == .instagram ? 120 : 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Auth headers: main app stores the latest Clerk bearer token in the shared container.
        guard let rawToken = SharedContainerManager.readAuthToken() else {
            throw ImportError.unauthorized
        }
        let token = rawToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { throw ImportError.unauthorized }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["url": urlString]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    // MARK: - Notification

    static func sendLocalNotification(title: String, body: String, success: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = success ? .default : UNNotificationSound(named: UNNotificationSoundName("error"))

        let request = UNNotificationRequest(
            identifier: "workout-import-\(UUID().uuidString)",
            content: content,
            trigger: nil // immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[URLImportService] Failed to schedule notification: \(error)")
            }
        }
    }

    // MARK: - Error Types

    enum ImportError: LocalizedError {
        case invalidURL
        case invalidResponse
        case unauthorized
        case serverError(Int, String)
        case decodingFailed(Error)
        case noURLsFound

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "That import link looks invalid. Check the URL and try again."
            case .invalidResponse: return "Unexpected response from the import service. Retry shortly."
            case .unauthorized: return "Not signed in. Open AmakaFlow, sign in, then share again."
            case .serverError(let code, let body):
                if code == 422 || code == 400 {
                    return "Couldn't parse that workout (\(code)): \(body.prefix(160))"
                }
                if code >= 500 {
                    return "Import service error (\(code)). Retry in a moment."
                }
                return "Import failed (\(code)): \(body.prefix(160))"
            case .decodingFailed:
                return "Couldn't read the import response. Retry or paste the link in Sources."
            case .noURLsFound:
                return "No URLs found in shared content. Share a link or paste text in Sources."
            }
        }
    }
}
