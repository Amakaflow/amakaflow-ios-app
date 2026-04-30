import Combine
import Foundation
import UIKit

/// Compatibility facade for legacy "pairing" call sites.
/// AMA-1620 replaces device-pairing JWTs with Clerk sessions; this service now mirrors Clerk auth state.
@MainActor
class PairingService: ObservableObject {
    static let shared = PairingService()

    @Published var isPaired: Bool = false
    @Published var userProfile: UserProfile?
    @Published var needsReauth: Bool = false
    @Published var lastTokenRefresh: Date?
    @Published var isInitialized: Bool = true

    private init() {
        bindAuthState()
    }

    private func bindAuthState() {
        let auth = AuthViewModel.shared
        isPaired = auth.isAuthenticated
        userProfile = auth.userProfile
        needsReauth = auth.needsReauth
        lastTokenRefresh = auth.lastTokenRefresh

        auth.$isAuthenticated
            .assign(to: &$isPaired)
        auth.$userProfile
            .assign(to: &$userProfile)
        auth.$needsReauth
            .assign(to: &$needsReauth)
        auth.$lastTokenRefresh
            .assign(to: &$lastTokenRefresh)
    }

    func markAuthInvalid() { AuthViewModel.shared.markAuthInvalid() }
    func authRestored() { AuthViewModel.shared.authRestored() }

    func registerAPNsToken(_ token: String) async {
        guard isPaired else {
            print("[PairingService] Not authenticated, skipping APNs token registration")
            return
        }
        guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else {
            print("[PairingService] No device ID available for APNs registration")
            return
        }
        do {
            try await APIService.shared.registerPushToken(apnsToken: token, deviceId: deviceId)
            print("[PairingService] APNs token registered successfully")
        } catch {
            print("[PairingService] APNs token registration failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func refreshToken() async -> Bool {
        await AuthViewModel.shared.refreshToken()
    }

    func pair(code: String) async throws -> PairingResponse {
        throw PairingError.invalidCode("Pairing codes are no longer supported. Please sign in with Clerk.")
    }

    func getToken() -> String? {
        AuthViewModel.shared.cachedBearerToken()
    }

    func unpair() {
        // Legacy synchronous API: signOut logs Clerk errors internally.
        Task { await AuthViewModel.shared.signOut() }
    }

    #if DEBUG
    func enableTestMode(authSecret: String, userId: String) {
        print("[PairingService] Test auth bypass was removed in AMA-1620. Use a real Clerk test user.")
    }

    func disableTestMode() {}

    var isInTestMode: Bool { UITestEnvironment.shared.hasClerkTestUser }
    #endif
}

struct PairingRequest: Codable {
    let token: String?
    let shortCode: String?
    let deviceInfo: DeviceInfo
}

struct DeviceInfo: Codable {
    let device: String
    let osVersion: String
    let appVersion: String
    let deviceId: String

    enum CodingKeys: String, CodingKey {
        case device
        case osVersion = "os"
        case appVersion
        case deviceId
    }
}

struct PairingResponse: Codable {
    let jwt: String
    let profile: UserProfile?
    let expiresAt: String
}

struct UserProfile: Codable {
    let id: String
    let email: String?
    let name: String?
    let avatarUrl: String?
}

struct APIErrorResponse: Codable {
    let detail: String
    let error: String?
    let message: String?
}

struct TokenRefreshRequest: Codable { let deviceId: String }
struct TokenRefreshResponse: Codable {
    let jwt: String
    let expiresAt: Date
    let refreshedAt: Date
}

enum PairingError: LocalizedError {
    case invalidCode(String)
    case codeExpired
    case invalidResponse
    case serverError(Int)
    case tokenStorageFailed

    var errorDescription: String? {
        switch self {
        case .invalidCode(let msg): return msg
        case .codeExpired: return "Code has expired. Please sign in again."
        case .invalidResponse: return "Invalid server response"
        case .serverError(let code): return "Server error: \(code)"
        case .tokenStorageFailed: return "Failed to save credentials"
        }
    }
}
