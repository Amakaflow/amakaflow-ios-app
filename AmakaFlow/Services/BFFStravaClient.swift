//
//  BFFStravaClient.swift
//  AmakaFlow
//
//  AMA-2391: mobile-BFF Strava surface — oauth initiate + sync-completed.
//

import Foundation

nonisolated enum BFFStravaClientError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case authenticationRequired
    case invalidResponse
    case httpError(statusCode: Int, detail: String?)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Strava service URL is invalid."
        case .authenticationRequired:
            return "Sign in again to connect Strava."
        case .invalidResponse:
            return "The Strava service returned an invalid response."
        case .httpError(let statusCode, let detail):
            return detail ?? "The Strava service request failed (\(statusCode))."
        case .decodingFailed:
            return "The Strava service returned data the app couldn't read."
        }
    }
}

struct StravaOAuthInitiateResponse: Codable, Equatable, Sendable {
    let url: String
}

struct StravaCompletedActivityDTO: Codable, Equatable, Sendable, Identifiable {
    var id: Int { stravaId }
    let stravaId: Int
    let name: String
    let type: String
    let distanceKm: Double
    let durationMin: Int
    /// UTC ISO8601 from Strava (`start_date`).
    let startDate: String
    /// Local wall-clock from Strava (`start_date_local`) when the BFF forwards it.
    /// AMA-2396: prefer this for day bucketing so UTC-crossing sessions land on the
    /// athlete's local day (the 18:34 / 12:19 regression).
    let startDateLocal: String?
    let description: String

    enum CodingKeys: String, CodingKey {
        case stravaId = "strava_id"
        case name
        case type
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case startDate = "start_date"
        case startDateLocal = "start_date_local"
        case description
    }

    init(
        stravaId: Int,
        name: String,
        type: String,
        distanceKm: Double,
        durationMin: Int,
        startDate: String,
        startDateLocal: String? = nil,
        description: String
    ) {
        self.stravaId = stravaId
        self.name = name
        self.type = type
        self.distanceKm = distanceKm
        self.durationMin = durationMin
        self.startDate = startDate
        self.startDateLocal = startDateLocal
        self.description = description
    }
}

struct StravaSyncCompletedResultDTO: Codable, Equatable, Sendable {
    let success: Bool
    let syncedCount: Int
    let activities: [StravaCompletedActivityDTO]
    let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case syncedCount = "synced_count"
        case activities
        case message
    }
}

struct StravaWriteBackAPIResultDTO: Codable, Equatable, Sendable {
    let activityId: Int
    let status: String
    let written: Bool

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case status
        case written
    }
}

struct StravaRestoreAPIResultDTO: Codable, Equatable, Sendable {
    let activityId: Int
    let restored: Bool
    let title: String
    let description: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case restored
        case title
        case description
        case message
    }

    init(
        activityId: Int,
        restored: Bool,
        title: String = "",
        description: String = "",
        message: String = ""
    ) {
        self.activityId = activityId
        self.restored = restored
        self.title = title
        self.description = description
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityId = try container.decode(Int.self, forKey: .activityId)
        restored = try container.decode(Bool.self, forKey: .restored)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
    }
}

private struct BFFStravaSyncCompletedBody: Encodable {
    let userId: String
    let daysBack: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case daysBack = "days_back"
    }
}

/// Production adapter for mobile-BFF `/v1/strava/*` (UPSTREAM_ROUTES).
nonisolated final class BFFStravaClient: @unchecked Sendable {
    typealias BearerTokenProvider = @Sendable () async throws -> String?
    typealias UserIDProvider = @Sendable () async throws -> String?

    private let baseURL: String
    private let session: URLSession
    private let bearerTokenProvider: BearerTokenProvider
    private let userIDProvider: UserIDProvider

    init(
        baseURL: String,
        session: URLSession = .shared,
        bearerTokenProvider: @escaping BearerTokenProvider,
        userIDProvider: @escaping UserIDProvider
    ) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = session
        self.bearerTokenProvider = bearerTokenProvider
        self.userIDProvider = userIDProvider
    }

    @MainActor
    static func live() -> BFFStravaClient {
        BFFStravaClient(
            baseURL: "\(AppEnvironment.current.mobileBFFURL)/v1",
            bearerTokenProvider: {
                try await AuthViewModel.shared.token()
            },
            userIDProvider: {
                await MainActor.run { AuthViewModel.shared.userProfile?.id }
            }
        )
    }

    /// POST `/v1/strava/oauth/initiate?userId=` → Strava authorize URL.
    /// - Parameter includeWrite: AMA-2396 write-back reconnect — request `activity:write`.
    func initiateOAuth(includeWrite: Bool = false) async throws -> URL {
        let userId = try await requireUserID()
        var query = [URLQueryItem(name: "userId", value: userId)]
        if includeWrite {
            query.append(URLQueryItem(name: "includeWrite", value: "true"))
        }
        let response: StravaOAuthInitiateResponse = try await send(
            method: "POST",
            path: "strava/oauth/initiate",
            queryItems: query,
            bodyData: nil
        )
        guard let url = URL(string: response.url) else {
            throw BFFStravaClientError.invalidURL
        }
        return url
    }

    /// POST `/v1/strava/sync-completed` — 30-day backfill on connect by default.
    func syncCompleted(daysBack: Int = 30) async throws -> StravaSyncCompletedResultDTO {
        let userId = try await requireUserID()
        let body = BFFStravaSyncCompletedBody(userId: userId, daysBack: daysBack)
        let bodyData = try JSONEncoder().encode(body)
        return try await send(
            method: "POST",
            path: "strava/sync-completed",
            queryItems: nil,
            bodyData: bodyData
        )
    }

    /// POST `/v1/strava/activities/{id}/writeback?userId=`
    func applyWriteBack(activityId: String) async throws -> StravaWriteBackAPIResultDTO {
        let userId = try await requireUserID()
        return try await send(
            method: "POST",
            path: "strava/activities/\(activityId)/writeback",
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            bodyData: nil
        )
    }

    /// POST `/v1/strava/activities/{id}/restore?userId=`
    func restoreWriteBack(activityId: String) async throws -> StravaRestoreAPIResultDTO {
        let userId = try await requireUserID()
        return try await send(
            method: "POST",
            path: "strava/activities/\(activityId)/restore",
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            bodyData: nil
        )
    }

    // MARK: - Private

    private func requireUserID() async throws -> String {
        guard let userId = try await userIDProvider(), !userId.isEmpty else {
            throw BFFStravaClientError.authenticationRequired
        }
        return userId
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?,
        bodyData: Data?
    ) async throws -> Response {
        var components = URLComponents(string: "\(baseURL)/\(path)")
        if let queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw BFFStravaClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let token = try await bearerTokenProvider(), !token.isEmpty else {
            throw BFFStravaClientError.authenticationRequired
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BFFStravaClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw BFFStravaClientError.authenticationRequired
            }
            let detail = String(data: data, encoding: .utf8)
            throw BFFStravaClientError.httpError(statusCode: http.statusCode, detail: detail)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BFFStravaClientError.decodingFailed(error.localizedDescription)
        }
    }
}
