//
//  StravaService.swift
//  AmakaFlow
//
//  Service for communicating with the strava-sync-api backend (port 8000).
//  Handles OAuth initiation, athlete info, and activity listing.
//  AMA-1235
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "StravaService")

// MARK: - Strava Data Models

struct StravaAthlete: Codable, Equatable {
    let id: Int
    let username: String
    let firstname: String
    let lastname: String
    let profile: String

    var displayName: String {
        "\(firstname) \(lastname)".trimmingCharacters(in: .whitespaces)
    }
}

struct StravaActivity: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let startDate: String
    let distance: Double
    let elapsedTime: Int
    let type: String

    /// Distance formatted in km
    var distanceKm: String {
        let km = distance / 1000.0
        return String(format: "%.1f km", km)
    }

    /// Duration formatted as mm:ss or h:mm:ss
    var durationFormatted: String {
        let hours = elapsedTime / 3600
        let minutes = (elapsedTime % 3600) / 60
        let seconds = elapsedTime % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Parsed date for display
    var dateFormatted: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: startDate) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        // Fallback: try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: startDate) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return startDate
    }

    /// SF Symbol name for the activity type
    var typeIcon: String {
        switch type.lowercased() {
        case "run": return "figure.run"
        case "ride", "virtualride": return "bicycle"
        case "swim": return "figure.pool.swim"
        case "walk", "hike": return "figure.walk"
        case "yoga": return "figure.mind.and.body"
        case "weighttraining": return "dumbbell.fill"
        case "workout": return "figure.strengthtraining.traditional"
        default: return "figure.mixed.cardio"
        }
    }
}

struct OAuthInitiateResponse: Codable {
    let url: String
}

// MARK: - Strava Service

class StravaService {
    static let shared = StravaService()

    private var baseURL: String { AppEnvironment.current.stravaAPIURL }
    private let session = URLSession.shared

    private init() {}

    // MARK: - User ID

    /// Get the current user ID from PairingService
    private var currentUserId: String? {
        PairingService.shared.userProfile?.id
    }

    // MARK: - Auth Headers

    private func authHeaders() async -> [String: String] {
        var headers = ["Content-Type": "application/json"]
        do {
            if let token = try await AuthViewModel.shared.token() {
                headers["Authorization"] = "Bearer \(token)"
            }
        } catch {
            print("[StravaService] Failed to get Clerk token: \(error.localizedDescription)")
        }
        return headers
    }

    // MARK: - OAuth Initiation

    /// Initiate Strava OAuth flow. Returns the authorization URL to open in a browser.
    func initiateOAuth() async throws -> URL {
        guard let userId = currentUserId else {
            throw StravaError.notAuthenticated
        }

        let urlString = "\(baseURL)/strava/oauth/initiate?userId=\(userId)"
        guard let url = URL(string: urlString) else {
            throw StravaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in await authHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("OAuth initiate failed: \(httpResponse.statusCode)")
            throw StravaError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(OAuthInitiateResponse.self, from: data)

        guard let authURL = URL(string: result.url) else {
            throw StravaError.invalidURL
        }

        logger.info("OAuth URL obtained for user \(userId)")
        return authURL
    }

    // MARK: - Get Athlete

    /// Fetch the connected Strava athlete profile.
    /// Returns nil if not connected (401/404).
    func getAthlete() async -> StravaAthlete? {
        guard let userId = currentUserId else {
            logger.warning("No user ID available for getAthlete")
            return nil
        }

        let urlString = "\(baseURL)/strava/athlete?userId=\(userId)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in await authHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 404 {
                // Not connected
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("getAthlete failed: \(httpResponse.statusCode)")
                return nil
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(StravaAthlete.self, from: data)
        } catch {
            logger.error("getAthlete error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Get Activities

    /// Fetch recent activities from Strava.
    func getActivities(limit: Int = 20) async throws -> [StravaActivity] {
        guard let userId = currentUserId else {
            throw StravaError.notAuthenticated
        }

        let urlString = "\(baseURL)/strava/activities?userId=\(userId)&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw StravaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in await authHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw StravaError.notAuthenticated
            }
            throw StravaError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([StravaActivity].self, from: data)
    }

    // MARK: - Disconnect (Clear local state)

    /// Disconnect Strava by clearing local connection state.
    /// Note: Full token revocation would require a backend endpoint.
    func disconnect() {
        logger.info("Strava disconnected locally")
    }
}

// MARK: - Errors

enum StravaError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case networkError(String)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please connect your Strava account."
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let code):
            return "Server error (\(code))"
        }
    }
}
