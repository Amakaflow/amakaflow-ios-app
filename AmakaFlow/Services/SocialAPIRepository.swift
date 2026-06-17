//
//  SocialAPIRepository.swift
//  AmakaFlow
//
//  AMA-1828: social-graph endpoints (feed, reactions, comments, settings,
//  user profile, follow/unfollow, challenges, crews, leaderboards) split
//  out of APIService.swift. Implemented as `extension APIService` so call
//  sites and APIServiceProviding conformance keep working unchanged.
//

import Foundation

extension APIService {

    // MARK: - Social Feed (AMA-1273)

    func fetchSocialFeed(cursor: String?, limit: Int) async throws -> FeedResponse {
        var urlString = "\(baseURL)/social/feed?limit=\(limit)"
        if let cursor = cursor {
            urlString += "&cursor=\(cursor)"
        }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(FeedResponse.self, from: data)
    }

    func addSocialReaction(postId: String, emoji: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/posts/\(postId)/react") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        request.httpBody = try JSONEncoder().encode(["emoji": emoji])
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func removeSocialReaction(postId: String, emoji: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/posts/\(postId)/react/\(emoji)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func fetchSocialComments(postId: String) async throws -> CommentsResponse {
        guard let url = URL(string: "\(baseURL)/social/posts/\(postId)/comments") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(CommentsResponse.self, from: data)
    }

    func postSocialComment(postId: String, text: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/posts/\(postId)/comment") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        request.httpBody = try JSONEncoder().encode(["text": text])
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func fetchSocialSettings() async throws -> SocialSettings {
        guard let url = URL(string: "\(baseURL)/social/settings") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(SocialSettings.self, from: data)
    }

    func updateSocialSettings(_ settings: SocialSettings) async throws {
        guard let url = URL(string: "\(baseURL)/social/settings") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(settings)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func fetchUserPublicProfile(userId: String) async throws -> UserPublicProfile {
        guard let url = URL(string: "\(baseURL)/social/users/\(userId)/profile") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(UserPublicProfile.self, from: data)
    }

    func followUser(userId: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/users/\(userId)/follow") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200, 204: return
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func unfollowUser(userId: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/users/\(userId)/unfollow") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200, 204: return
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Challenges (AMA-1276)

    func fetchChallenges() async throws -> ChallengesResponse {
        guard let url = URL(string: "\(baseURL)/social/challenges") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(ChallengesResponse.self, from: data)
    }

    func fetchChallengeDetail(id: String) async throws -> ChallengeDetailResponse {
        guard let url = URL(string: "\(baseURL)/social/challenges/\(id)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(ChallengeDetailResponse.self, from: data)
    }

    func createChallenge(_ request: CreateChallengeRequest) async throws {
        guard let url = URL(string: "\(baseURL)/social/challenges") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func joinChallenge(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/challenges/\(id)/join") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - Training Crews (AMA-1277)

    func fetchMyCrews() async throws -> CrewListResponse {
        guard let url = URL(string: "\(baseURL)/social/crews") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(CrewListResponse.self, from: data)
    }

    func fetchCrewDetail(id: String) async throws -> CrewDetail {
        guard let url = URL(string: "\(baseURL)/social/crews/\(id)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(CrewDetail.self, from: data)
    }

    func fetchCrewFeed(crewId: String) async throws -> CrewFeedResponse {
        guard let url = URL(string: "\(baseURL)/social/crews/\(crewId)/feed") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(CrewFeedResponse.self, from: data)
    }

    func createCrew(_ request: CreateCrewRequest) async throws {
        guard let url = URL(string: "\(baseURL)/social/crews") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func joinCrew(crewId: String, request: JoinCrewRequest) async throws {
        guard let url = URL(string: "\(baseURL)/social/crews/\(crewId)/join") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func leaveCrew(crewId: String) async throws {
        guard let url = URL(string: "\(baseURL)/social/crews/\(crewId)/leave") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (_, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - Leaderboards (AMA-1278)

    func fetchFriendsLeaderboard(dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        guard let url = URL(string: "\(baseURL)/social/leaderboards/friends?dimension=\(dimension)&period=\(period)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(LeaderboardAPIResponse.self, from: data)
    }

    func fetchCrewLeaderboard(crewId: String, dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        guard let url = URL(string: "\(baseURL)/social/leaderboards/crew/\(crewId)?dimension=\(dimension)&period=\(period)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode(LeaderboardAPIResponse.self, from: data)
    }
}
