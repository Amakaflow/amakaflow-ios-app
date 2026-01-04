import Foundation
import UIKit
import Combine

@MainActor
class PairingService: ObservableObject {
    static let shared = PairingService()

    private let baseURL = AppEnvironment.current.mapperAPIURL
    private let tokenKey = "jwt_token"
    private let profileKey = "user_profile"
    private let tokenRefreshKey = "last_token_refresh"

    @Published var isPaired: Bool = false
    @Published var userProfile: UserProfile?
    @Published var needsReauth: Bool = false
    @Published var lastTokenRefresh: Date?

    private init() {
        // Handle E2E test auth bypass (AMA-232)
        // Check for test mode BEFORE setting isPaired so SwiftUI sees the correct initial state
        #if DEBUG
        let hasUITesting = CommandLine.arguments.contains("--uitesting")
        let hasSkipPairing = CommandLine.arguments.contains("--skip-pairing")
        print("[PairingService] Init - hasUITesting=\(hasUITesting), hasSkipPairing=\(hasSkipPairing)")

        if hasUITesting && hasSkipPairing {
            // Check for X-Test-Auth header bypass (preferred - no token expiry)
            if let testAuthSecret = ProcessInfo.processInfo.environment["TEST_AUTH_SECRET"],
               let testUserId = ProcessInfo.processInfo.environment["TEST_USER_ID"],
               !testAuthSecret.isEmpty {
                print("[E2E] Using X-Test-Auth header bypass for user: \(testUserId)")
                // Set isPaired directly since auth is via headers, not token
                isPaired = true
                userProfile = loadProfile()
                lastTokenRefresh = loadLastTokenRefresh()
                print("[PairingService] E2E mode initialized with isPaired=true (X-Test-Auth)")
                return
            }

            // Legacy: JWT token in keychain (has expiry issues)
            if let testToken = ProcessInfo.processInfo.environment["TEST_JWT"] {
                print("[E2E] Found TEST_JWT, length=\(testToken.count)")
                let saveResult = KeychainHelper.shared.save(testToken, for: tokenKey)
                if saveResult {
                    print("[E2E] Test JWT stored in keychain during PairingService init")
                }
            }
        }
        #endif

        isPaired = getToken() != nil
        userProfile = loadProfile()
        lastTokenRefresh = loadLastTokenRefresh()

        #if DEBUG
        print("[PairingService] Initialized with isPaired=\(isPaired), hasToken=\(getToken() != nil)")
        #endif
    }

    /// Mark authentication as invalid (e.g., on 401 response)
    /// This preserves queued data while signaling that re-pairing is needed
    func markAuthInvalid() {
        needsReauth = true
        // Don't clear isPaired immediately - let the UI handle showing re-pair prompt
        // The queued completions will be processed after re-pairing
    }

    /// Called after successful re-pairing to clear the needsReauth flag
    func authRestored() {
        needsReauth = false
    }

    // MARK: - Token Refresh

    /// Silently refresh the JWT using device ID
    /// Returns true if refresh succeeded, false if device not found (needs re-pair)
    func refreshToken() async -> Bool {
        guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else {
            print("[PairingService] No device ID available for refresh")
            return false
        }

        print("[PairingService] Attempting silent token refresh")

        let url = URL(string: "\(baseURL)/mobile/pairing/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = TokenRefreshRequest(deviceId: deviceId)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        do {
            request.httpBody = try encoder.encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[PairingService] Invalid response type during refresh")
                return false
            }

            print("[PairingService] Refresh response status = \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601
                let result = try decoder.decode(TokenRefreshResponse.self, from: data)

                try storeToken(result.jwt)
                storeLastTokenRefresh(result.refreshedAt)

                await MainActor.run {
                    self.needsReauth = false
                    self.lastTokenRefresh = result.refreshedAt
                }

                print("[PairingService] Token refreshed successfully")

                // Process any queued workout completions after refresh
                Task {
                    await WorkoutCompletionService.shared.retryPendingCompletions()
                }

                return true

            case 401:
                // Device not found or not paired - need to re-pair
                print("[PairingService] Refresh failed: device not found")
                await MainActor.run {
                    self.needsReauth = true
                }
                return false

            default:
                print("[PairingService] Refresh failed with status \(httpResponse.statusCode)")
                return false
            }
        } catch {
            print("[PairingService] Refresh error: \(error)")
            return false
        }
    }

    // MARK: - Pairing

    /// Exchange a pairing code (from QR or manual entry) for a JWT
    func pair(code: String) async throws -> PairingResponse {
        print("[PairingService] Starting pair request to \(baseURL)")

        let url = URL(string: "\(baseURL)/mobile/pairing/pair")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Send code in appropriate field based on length:
        // - 6 chars = short_code (manual entry)
        // - > 6 chars = token (from QR code)
        let isShortCode = code.count == 6
        let modelIdentifier = getDeviceModel()
        let body = PairingRequest(
            token: isShortCode ? nil : code,
            shortCode: isShortCode ? code.uppercased() : nil,
            deviceInfo: DeviceInfo(
                device: getDeviceName(for: modelIdentifier),
                os: "iOS \(UIDevice.current.systemVersion)",
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            )
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(body)
        request.httpBody = bodyData

        // Log the request body for debugging
        if let bodyString = String(data: bodyData, encoding: .utf8) {
            print("[PairingService] Request body: \(bodyString)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log the response body for debugging
        if let responseBody = String(data: data, encoding: .utf8) {
            print("[PairingService] Response body: \(responseBody)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[PairingService] Invalid response type")
            throw PairingError.invalidResponse
        }

        print("[PairingService] Response status = \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(PairingResponse.self, from: data)
            try storeToken(result.jwt)
            print("[PairingService] JWT stored successfully")
            if let profile = result.profile {
                storeProfile(profile)
            }
            await MainActor.run {
                self.isPaired = true
                self.userProfile = result.profile
                self.needsReauth = false

                // Set Sentry user context for error tracking (AMA-225)
                if let profile = result.profile {
                    SentryService.shared.setUser(userId: profile.id, email: profile.email)
                    SentryService.shared.trackPairingAction("Device paired successfully")
                }
            }
            // Process any queued workout completions after re-pairing
            Task {
                await WorkoutCompletionService.shared.retryPendingCompletions()
            }
            return result
        case 400:
            let error = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            print("[PairingService] Invalid code: \(error?.detail ?? "unknown")")
            throw PairingError.invalidCode(error?.detail ?? "Invalid code")
        case 410:
            print("[PairingService] Code expired")
            throw PairingError.codeExpired
        default:
            print("[PairingService] Server error \(httpResponse.statusCode)")
            throw PairingError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Token Management

    func storeToken(_ jwt: String) throws {
        if !KeychainHelper.shared.save(jwt, for: tokenKey) {
            throw PairingError.tokenStorageFailed
        }
    }

    func getToken() -> String? {
        return KeychainHelper.shared.readString(for: tokenKey)
    }

    func unpair() {
        KeychainHelper.shared.delete(for: tokenKey)
        KeychainHelper.shared.delete(for: profileKey)
        Task { @MainActor in
            self.isPaired = false
            self.userProfile = nil

            // Clear Sentry user context (AMA-225)
            SentryService.shared.trackPairingAction("Device unpaired")
            SentryService.shared.clearUser()
        }
    }

    // MARK: - Profile Storage

    private func storeProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            _ = KeychainHelper.shared.save(data, for: profileKey)
        }
    }

    private func loadProfile() -> UserProfile? {
        guard let data = KeychainHelper.shared.read(for: profileKey) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    // MARK: - Token Refresh Timestamp Storage

    private func storeLastTokenRefresh(_ date: Date) {
        UserDefaults.standard.set(date, forKey: tokenRefreshKey)
    }

    private func loadLastTokenRefresh() -> Date? {
        return UserDefaults.standard.object(forKey: tokenRefreshKey) as? Date
    }

    // MARK: - Device Info

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    private func getDeviceName(for identifier: String) -> String {
        // Map device identifiers to friendly names
        // See: https://gist.github.com/adamawolf/3048717
        let deviceNames: [String: String] = [
            // iPhone
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            "iPhone18,1": "iPhone 17 Pro",
            "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17",
            "iPhone18,4": "iPhone 17 Plus",
            "iPhone18,5": "iPhone 17 Air",
            // iPad
            "iPad13,4": "iPad Pro 11-inch (3rd gen)",
            "iPad13,5": "iPad Pro 11-inch (3rd gen)",
            "iPad13,6": "iPad Pro 11-inch (3rd gen)",
            "iPad13,7": "iPad Pro 11-inch (3rd gen)",
            "iPad13,8": "iPad Pro 12.9-inch (5th gen)",
            "iPad13,9": "iPad Pro 12.9-inch (5th gen)",
            "iPad13,10": "iPad Pro 12.9-inch (5th gen)",
            "iPad13,11": "iPad Pro 12.9-inch (5th gen)",
            "iPad14,1": "iPad mini (6th gen)",
            "iPad14,2": "iPad mini (6th gen)",
            "iPad14,3": "iPad Pro 11-inch (4th gen)",
            "iPad14,4": "iPad Pro 11-inch (4th gen)",
            "iPad14,5": "iPad Pro 12.9-inch (6th gen)",
            "iPad14,6": "iPad Pro 12.9-inch (6th gen)",
            // Simulator
            "x86_64": "Simulator",
            "arm64": "Simulator"
        ]

        return deviceNames[identifier] ?? identifier
    }
}

// MARK: - Models

struct PairingRequest: Codable {
    let token: String?
    let shortCode: String?
    let deviceInfo: DeviceInfo
}

struct DeviceInfo: Codable {
    let device: String      // Friendly name like "iPhone 15 Pro"
    let os: String          // Formatted like "iOS 17.2"
    let appVersion: String  // App version like "1.0.17"
    let deviceId: String    // Unique device identifier
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

struct TokenRefreshRequest: Codable {
    let deviceId: String
}

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
        case .codeExpired: return "Code has expired. Please generate a new one."
        case .invalidResponse: return "Invalid server response"
        case .serverError(let code): return "Server error: \(code)"
        case .tokenStorageFailed: return "Failed to save credentials"
        }
    }
}
