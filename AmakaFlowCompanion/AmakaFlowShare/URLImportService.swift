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
/// Uses a background URLSession so the request survives extension termination.
final class URLImportService: NSObject {

    static let shared = URLImportService()

    /// Completion handler stashed by the system for background session events
    var backgroundCompletionHandler: (() -> Void)?

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.amakaflow.share.import")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.shouldUseExtendedBackgroundIdleMode = true
        // Share extensions have limited memory — keep timeouts reasonable
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Non-background session for immediate inline requests (used when the extension is still alive)
    private lazy var immediateSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Import a single URL using an immediate (non-background) request.
    /// Returns the parsed response inline.
    func importURL(_ urlString: String, platform: DetectedPlatform) async throws -> ShareIngestResponse {
        let request = try buildRequest(for: urlString, platform: platform)

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

    /// Fire-and-forget import via background session.
    /// Result will be delivered via delegate callbacks even if the extension is terminated.
    func importURLInBackground(_ urlString: String, platform: DetectedPlatform) throws {
        let request = try buildRequest(for: urlString, platform: platform)

        // Stash metadata so we can match the task later
        let metadata = BackgroundTaskMetadata(url: urlString, platform: platform.name)
        if let metadataData = try? JSONEncoder().encode(metadata) {
            UserDefaults(suiteName: SharedContainerManager.suiteName)?
                .set(metadataData, forKey: "bg_task_\(urlString.hashValue)")
        }

        backgroundSession.dataTask(with: request).resume()
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Auth headers
        if let testAuth = SharedContainerManager.readTestAuth() {
            request.setValue(testAuth.secret, forHTTPHeaderField: "X-Test-Auth")
            request.setValue(testAuth.userId, forHTTPHeaderField: "X-Test-User-Id")
        } else if let token = SharedContainerManager.readAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw ImportError.unauthorized
        }

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
            case .invalidURL: return "Invalid URL"
            case .invalidResponse: return "Invalid server response"
            case .unauthorized: return "Not signed in. Open AmakaFlow and sign in first."
            case .serverError(let code, let body):
                return "Server error (\(code)): \(body.prefix(200))"
            case .decodingFailed(let error):
                return "Failed to parse response: \(error.localizedDescription)"
            case .noURLsFound:
                return "No URLs found in shared content"
            }
        }
    }
}

// MARK: - Background Session Metadata

private struct BackgroundTaskMetadata: Codable {
    let url: String
    let platform: String
}

// MARK: - URLSessionDelegate (background session callbacks)

extension URLImportService: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let originalURL = task.originalRequest?.url?.absoluteString ?? "unknown"

        if let error {
            // Network failure
            let result = SharedContainerManager.ImportResult(
                url: originalURL,
                platform: "unknown",
                title: nil,
                workoutType: nil,
                success: false,
                errorMessage: error.localizedDescription,
                timestamp: Date()
            )
            SharedContainerManager.saveImportResult(result)

            URLImportService.sendLocalNotification(
                title: "Import Failed",
                body: "Could not import workout: \(error.localizedDescription)",
                success: false
            )
        }

        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let originalURL = dataTask.originalRequest?.url?.absoluteString ?? "unknown"
        let statusCode = (dataTask.response as? HTTPURLResponse)?.statusCode ?? 0

        if (200..<300).contains(statusCode) {
            let response = try? JSONDecoder().decode(ShareIngestResponse.self, from: data)
            let result = SharedContainerManager.ImportResult(
                url: originalURL,
                platform: response?.source ?? "unknown",
                title: response?.title,
                workoutType: response?.workoutType,
                success: true,
                errorMessage: nil,
                timestamp: Date()
            )
            SharedContainerManager.saveImportResult(result)

            URLImportService.sendLocalNotification(
                title: "Workout Imported",
                body: response?.title ?? "Workout imported successfully",
                success: true
            )
        } else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let result = SharedContainerManager.ImportResult(
                url: originalURL,
                platform: "unknown",
                title: nil,
                workoutType: nil,
                success: false,
                errorMessage: "Server error (\(statusCode)): \(body.prefix(200))",
                timestamp: Date()
            )
            SharedContainerManager.saveImportResult(result)

            URLImportService.sendLocalNotification(
                title: "Import Failed",
                body: "Server returned error \(statusCode)",
                success: false
            )
        }
    }
}
