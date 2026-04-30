import Foundation

struct ClerkAuthorizationInterceptor {
    static func injectAuthorization(into request: inout URLRequest) async throws {
        guard request.value(forHTTPHeaderField: "Authorization") == nil else { return }
        if let token = try await AuthViewModel.shared.token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

extension URLRequest {
    mutating func injectClerkAuthorization() async throws {
        try await ClerkAuthorizationInterceptor.injectAuthorization(into: &self)
    }
}
