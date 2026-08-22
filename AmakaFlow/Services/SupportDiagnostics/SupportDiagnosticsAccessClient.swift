import Foundation

nonisolated protocol SupportDiagnosticsAccessProviding: Sendable {
    func fetchAccess() async throws -> SupportDiagnosticsAccess
    func startSession(
        idempotencyKey: String,
        requestID: String?
    ) async throws -> SupportDiagnosticsAuditEvent
}

nonisolated enum SupportDiagnosticsClientError: LocalizedError, Equatable, Sendable {
    case authenticationRequired
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Sign in again to check Support Diagnostics access."
        case .invalidResponse:
            return "Support Diagnostics returned an invalid response."
        case .httpStatus:
            return "Support Diagnostics is temporarily unavailable."
        case .decodingFailed:
            return "Support Diagnostics returned data the app could not read."
        }
    }
}

nonisolated final class SupportDiagnosticsAccessClient: SupportDiagnosticsAccessProviding, @unchecked Sendable {
    typealias BearerTokenProvider = @Sendable () async throws -> String?

    private let baseURL: URL
    private let session: URLSession
    private let appVersion: String
    private let bearerTokenProvider: BearerTokenProvider

    init(
        baseURL: URL,
        session: URLSession = .shared,
        appVersion: String,
        bearerTokenProvider: @escaping BearerTokenProvider
    ) {
        self.baseURL = baseURL
        self.session = session
        self.appVersion = appVersion
        self.bearerTokenProvider = bearerTokenProvider
    }

    @MainActor
    static func live() -> SupportDiagnosticsAccessClient? {
        guard let baseURL = URL(string: "\(AppEnvironment.current.mobileBFFURL)/v1") else {
            return nil
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return SupportDiagnosticsAccessClient(
            baseURL: baseURL,
            appVersion: "\(version) (\(build))"
        ) {
            try await AuthViewModel.shared.token()
        }
    }

    func fetchAccess() async throws -> SupportDiagnosticsAccess {
        let response: AccessResponse = try await send(
            method: "GET",
            path: "support-diagnostics/access"
        )
        return SupportDiagnosticsAccess(
            enabled: response.enabled,
            grantID: response.grantID,
            role: response.role,
            capabilities: Set(response.capabilities.compactMap(SupportDiagnosticsCapability.init(rawValue:))),
            expiresAt: response.expiresAt,
            serverTime: response.serverTime
        )
    }

    func startSession(
        idempotencyKey: String,
        requestID: String?
    ) async throws -> SupportDiagnosticsAuditEvent {
        let response: AuditEventResponse = try await send(
            method: "POST",
            path: "support-diagnostics/sessions/start",
            idempotencyKey: idempotencyKey,
            requestID: requestID
        )
        return SupportDiagnosticsAuditEvent(
            auditID: response.auditID,
            eventType: response.eventType,
            outcome: response.outcome,
            createdAt: response.createdAt
        )
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        idempotencyKey: String? = nil,
        requestID: String? = nil
    ) async throws -> Response {
        guard let token = try await bearerTokenProvider(), !token.isEmpty else {
            throw SupportDiagnosticsClientError.authenticationRequired
        }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(appVersion, forHTTPHeaderField: "X-AmakaFlow-App-Version")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let requestID {
            request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupportDiagnosticsClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw SupportDiagnosticsClientError.authenticationRequired
            }
            throw SupportDiagnosticsClientError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SupportDiagnosticsClientError.decodingFailed
        }
    }
}

private nonisolated struct AccessResponse: Decodable {
    let enabled: Bool
    let grantID: UUID?
    let role: SupportDiagnosticsRole?
    let capabilities: [String]
    let expiresAt: Date?
    let serverTime: Date

    private enum CodingKeys: String, CodingKey {
        case enabled
        case grantID = "grantId"
        case role
        case capabilities
        case expiresAt
        case serverTime
    }
}

private nonisolated struct AuditEventResponse: Decodable {
    let auditID: UUID
    let eventType: SupportDiagnosticsAuditEventType
    let outcome: SupportDiagnosticsAuditOutcome
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case auditID = "auditId"
        case eventType
        case outcome
        case createdAt
    }
}
