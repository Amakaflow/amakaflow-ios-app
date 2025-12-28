import Foundation
import UIKit
import Combine

@MainActor
class PairingService: ObservableObject {
    static let shared = PairingService()

    private let baseURL = AppEnvironment.current.mapperAPIURL
    private let tokenKey = "jwt_token"
    private let profileKey = "user_profile"

    @Published var isPaired: Bool = false
    @Published var userProfile: UserProfile?

    private init() {
        isPaired = getToken() != nil
        userProfile = loadProfile()
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
