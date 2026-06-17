//
//  DeviceAPIRepository.swift
//  AmakaFlow
//
//  AMA-1828: Device + user-account endpoints (mobile/profile,
//  watch-delivery/resend, mobile/devices/register-push-token, privacy
//  export/delete) extracted from APIService.swift. Implemented as
//  `extension APIService` so existing call sites and the
//  APIServiceProviding conformance keep working unchanged.
//
//  Endpoints:
//    POST   /api/watch-delivery/resend
//    POST   /mobile/devices/register-push-token
//    GET    /mobile/profile
//    GET    /api/privacy/export
//    DELETE /account
//

import Foundation

extension APIService {

    // MARK: - Watch Delivery

    func resendWatchDelivery() async throws {
        guard let url = URL(string: "\(baseURL)/api/watch-delivery/resend") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Push Token Registration (AMA-567)

    /// Register APNs push token with the backend for silent push notifications
    /// - Parameters:
    ///   - apnsToken: Hex-encoded APNs device token from Apple
    ///   - deviceId: iOS device UUID (identifierForVendor)
    /// - Throws: APIError if request fails
    func registerPushToken(apnsToken: String, deviceId: String) async throws {
        guard PairingService.shared.isPaired else {
            throw APIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/mobile/devices/register-push-token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let body: [String: Any] = [
            "apns_token": apnsToken,
            "device_id": deviceId,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[APIService] Registering push token")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 201:
            print("[APIService] Push token registered successfully")
            return
        case 401:
            throw APIError.unauthorized
        default:
            let responseString = String(data: data, encoding: .utf8)
            logError(endpoint: "/mobile/devices/register-push-token", method: "POST", statusCode: httpResponse.statusCode, response: responseString, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - User Profile

    /// Fetch user profile from backend
    /// - Returns: UserProfile if successful
    /// - Throws: APIError if request fails
    func fetchProfile() async throws -> UserProfile {
        let url = URL(string: "\(baseURL)/mobile/profile")!
        print("[APIService] Fetching profile from: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[APIService] Invalid response type")
            throw APIError.invalidResponse
        }

        print("[APIService] Profile response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let profileResponse = try decoder.decode(ProfileResponse.self, from: data)
                return profileResponse.profile
            } catch {
                print("[APIService] Profile decoding error: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[APIService] Response body: \(responseString.prefix(500))")
                }
                throw APIError.decodingError(error)
            }
        case 401:
            print("[APIService] Unauthorized (401)")
            throw APIError.unauthorized
        default:
            if let responseString = String(data: data, encoding: .utf8) {
                print("[APIService] Error response: \(responseString.prefix(200))")
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Privacy (AMA-1608)

    /// Export the authenticated user's full account data as JSON.
    func exportUserData() async throws -> Data {
        guard let url = URL(string: "\(baseURL)/api/privacy/export") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(httpResponse.statusCode)
        }
        return data
    }

    /// Delete the authenticated account and all associated backend data.
    func deleteAccount() async throws {
        guard let url = URL(string: "\(baseURL)/account") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/account", method: "DELETE", statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
