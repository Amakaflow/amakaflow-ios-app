import Foundation

/// Provides bearer tokens and supports a forced refresh after a 401 response.
/// Implemented by `ClerkTokenRefreshCoordinator`; also used in tests via mocks.
protocol ClerkBearerTokenProvider: Sendable {
    func bearerToken() async throws -> String
    func refreshAfterUnauthorized() async throws -> String
}

extension ClerkTokenRefreshCoordinator: ClerkBearerTokenProvider {}

struct ClerkAuthorizationInterceptor {
    static func injectAuthorization(into request: inout URLRequest) async throws {
        guard request.value(forHTTPHeaderField: "Authorization") == nil else { return }
        if let token = try await AuthViewModel.shared.token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Executes `request` with a 401→refresh→retry-once guard.
    ///
    /// On a 401 response the token provider's `refreshAfterUnauthorized()` is
    /// called exactly once and the request is retried with the new token. If
    /// the retry also returns 401, `APIError.unauthorized` is thrown — the
    /// loop never fires a second time. Any other status code is returned as-is.
    static func perform(
        _ request: URLRequest,
        tokenProvider: ClerkBearerTokenProvider,
        session: APIURLSession
    ) async throws -> (Data, HTTPURLResponse) {
        var authed = request
        let token = try await tokenProvider.bearerToken()
        authed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: authed)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }
        guard http.statusCode == 401 else {
            return (data, http)
        }

        // 401 — refresh token and retry exactly once
        let freshToken = try await tokenProvider.refreshAfterUnauthorized()
        var retry = request
        retry.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")

        let (retryData, retryResponse) = try await session.data(for: retry)
        guard let retryHttp = retryResponse as? HTTPURLResponse else {
            throw APIError.unknown
        }
        if retryHttp.statusCode == 401 {
            throw APIError.unauthorized
        }
        return (retryData, retryHttp)
    }
}

extension URLRequest {
    mutating func injectClerkAuthorization() async throws {
        try await ClerkAuthorizationInterceptor.injectAuthorization(into: &self)
    }
}
