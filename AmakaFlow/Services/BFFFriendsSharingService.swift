//
//  BFFFriendsSharingService.swift
//  AmakaFlow
//
//  AMA-2390: Live mobile-BFF adapter for friends and immutable workout shares.
//

import Foundation

nonisolated enum BFFFriendsSharingServiceError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case authenticationRequired
    case invalidResponse
    case httpError(statusCode: Int, detail: String?)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The friends service URL is invalid."
        case .authenticationRequired:
            return "Sign in again to use friends and workout sharing."
        case .invalidResponse:
            return "The friends service returned an invalid response."
        case .httpError(let statusCode, let detail):
            return detail ?? "The friends service request failed (\(statusCode))."
        case .decodingFailed:
            return "The friends service returned data the app couldn't read."
        }
    }
}

/// Production adapter for the mobile-BFF `/v1/friends` and `/v1/shares` contract.
///
/// The service never falls back to local fixtures. A missing token, transport
/// failure, non-2xx response, or malformed payload is surfaced to the caller.
nonisolated final class BFFFriendsSharingService: FriendsSharingProviding, @unchecked Sendable {
    typealias BearerTokenProvider = @Sendable () async throws -> String?

    private let baseURL: String
    private let session: URLSession
    private let bearerTokenProvider: BearerTokenProvider

    init(
        baseURL: String,
        session: URLSession = .shared,
        bearerTokenProvider: @escaping BearerTokenProvider
    ) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = session
        self.bearerTokenProvider = bearerTokenProvider
    }

    @MainActor
    static func live() -> BFFFriendsSharingService {
        BFFFriendsSharingService(
            baseURL: "\(AppEnvironment.current.mobileBFFURL)/v1"
        ) {
            try await AuthViewModel.shared.token()
        }
    }

    // MARK: - FriendshipProviding

    func listFriendships() async throws -> [Friendship] {
        let response: FriendshipListEnvelope = try await send(
            method: "GET",
            pathComponents: ["friends"]
        )
        return response.friendships
    }

    func searchUsers(query: String) async throws -> [FriendProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: FriendProfileListEnvelope = try await send(
            method: "GET",
            pathComponents: ["friends", "search"],
            queryItems: [URLQueryItem(name: "handle", value: trimmed)]
        )
        return response.profiles
    }

    func requestFriend(handle: String) async throws -> Friendship {
        try await send(
            method: "POST",
            pathComponents: ["friends", "requests"],
            body: FriendRequestBody(handle: handle)
        )
    }

    func acceptRequest(id: String) async throws -> Friendship {
        try await send(
            method: "POST",
            pathComponents: ["friends", "requests", id, "accept"]
        )
    }

    func declineRequest(id: String) async throws {
        try await sendWithoutResponse(
            method: "POST",
            pathComponents: ["friends", "requests", id, "decline"]
        )
    }

    func cancelRequest(id: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            pathComponents: ["friends", "requests", id]
        )
    }

    func removeFriend(id: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            pathComponents: ["friends", id]
        )
    }

    func inviteLink() async throws -> URL {
        // The AMA-2390 BFF contract has no invite-link endpoint and the
        // FriendsSharingProviding seam does not supply the current Clerk handle.
        // Fail explicitly instead of fabricating an account URL.
        throw FriendsSharingError.inviteHandleMissing
    }

    // MARK: - WorkoutShareProviding

    func listIncomingShares() async throws -> [WorkoutShare] {
        try await shareInbox().shares
    }

    func unhandledShareCount() async throws -> Int {
        try await shareInbox().unhandledCount
    }

    func sendShares(
        snapshot: WorkoutShareSnapshot,
        toFriendIds: [String],
        note: String?
    ) async throws -> [WorkoutShare] {
        guard !toFriendIds.isEmpty else {
            throw FriendsSharingError.emptySelection
        }
        let response: WorkoutShareListEnvelope = try await send(
            method: "POST",
            pathComponents: ["shares"],
            body: WorkoutShareCreateBody(
                toFriendIds: toFriendIds,
                snapshot: snapshot,
                note: note
            )
        )
        return response.shares
    }

    func markSeen(id: String) async throws {
        let _: ShareStatusEnvelope = try await send(
            method: "POST",
            pathComponents: ["shares", id, "seen"]
        )
    }

    func dismiss(id: String) async throws {
        let _: ShareStatusEnvelope = try await send(
            method: "POST",
            pathComponents: ["shares", id, "dismiss"]
        )
    }

    func saveRequest(id: String, titleOverride: String?) async throws -> WorkoutSaveRequest {
        let inbox = try await shareInbox()
        guard let share = inbox.shares.first(where: { $0.id == id }) else {
            throw FriendsSharingError.notFound
        }
        return WorkoutSaveRequest(
            name: titleOverride ?? share.snapshot.name,
            sport: share.snapshot.sport,
            intervals: share.snapshot.intervals,
            source: WorkoutSource.friend.rawValue,
            sourceUrl: share.snapshot.sourceUrl,
            description: share.snapshot.description,
            creatorName: share.fromDisplayName,
            blocks: share.snapshot.blocks,
            workoutId: share.savedWorkoutId
        )
    }

    func markSaved(id: String, workoutId: String) async throws {
        let _: ShareStatusEnvelope = try await send(
            method: "POST",
            pathComponents: ["shares", id, "save"],
            body: ShareSaveBody(savedWorkoutId: workoutId)
        )
    }

    // MARK: - Transport

    private func shareInbox() async throws -> WorkoutShareListEnvelope {
        try await send(
            method: "GET",
            pathComponents: ["shares", "inbox"]
        )
    }

    private func send<Response: Decodable>(
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await sendData(
            method: method,
            pathComponents: pathComponents,
            queryItems: queryItems,
            body: nil
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        return try await sendData(
            method: method,
            pathComponents: pathComponents,
            queryItems: queryItems,
            body: data
        )
    }

    private func sendWithoutResponse(
        method: String,
        pathComponents: [String]
    ) async throws {
        let request = try await makeRequest(
            method: method,
            pathComponents: pathComponents,
            queryItems: [],
            body: nil
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func sendData<Response: Decodable>(
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem],
        body: Data?
    ) async throws -> Response {
        let request = try await makeRequest(
            method: method,
            pathComponents: pathComponents,
            queryItems: queryItems,
            body: body
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        do {
            return try APIService.makeGeneratedDecoder().decode(Response.self, from: data)
        } catch {
            throw BFFFriendsSharingServiceError.decodingFailed(error.localizedDescription)
        }
    }

    private func makeRequest(
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem],
        body: Data?
    ) async throws -> URLRequest {
        guard var url = URL(string: baseURL) else {
            throw BFFFriendsSharingServiceError.invalidURL
        }
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BFFFriendsSharingServiceError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let requestURL = components.url else {
            throw BFFFriendsSharingServiceError.invalidURL
        }

        guard let token = try await bearerTokenProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty else {
            throw BFFFriendsSharingServiceError.authenticationRequired
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw BFFFriendsSharingServiceError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw BFFFriendsSharingServiceError.authenticationRequired
            }
            let detail = try? JSONDecoder().decode(ErrorEnvelope.self, from: data).detail
            throw BFFFriendsSharingServiceError.httpError(
                statusCode: response.statusCode,
                detail: detail
            )
        }
    }

    private struct FriendshipListEnvelope: Decodable {
        let friendships: [Friendship]
    }

    private struct FriendProfileListEnvelope: Decodable {
        let profiles: [FriendProfile]
    }

    private struct WorkoutShareListEnvelope: Decodable {
        let shares: [WorkoutShare]
        let unhandledCount: Int
    }

    private struct ShareStatusEnvelope: Decodable {
        let id: String
        let status: WorkoutShareStatus
        let savedWorkoutId: String?
    }

    private struct FriendRequestBody: Encodable {
        let handle: String
    }

    private struct WorkoutShareCreateBody: Encodable {
        let toFriendIds: [String]
        let snapshot: WorkoutShareSnapshot
        let note: String?
    }

    private struct ShareSaveBody: Encodable {
        let savedWorkoutId: String
    }

    private struct ErrorEnvelope: Decodable {
        let detail: String
    }
}
