//
//  TelegramAPIRepository.swift
//  AmakaFlow
//
//  AMA-1828: Telegram link-token / link-status endpoints, extracted from
//  the monolithic APIService.swift. Implemented as `extension APIService`
//  so the existing `APIService: APIServiceProviding` conformance and all
//  call sites (`APIService.shared.mintTelegramLinkToken()`, etc.) keep
//  working unchanged. Pure refactor — no behaviour change.
//
//  Endpoints:
//    POST  /api/telegram/link-token
//    GET   /api/telegram/link-status?token=…
//

import Foundation

extension APIService {

    // MARK: - Telegram Linking

    func mintTelegramLinkToken() async throws -> TelegramLinkTokenResponse {
        guard let url = URL(string: "\(baseURL)/api/telegram/link-token") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try APIService.makeDecoder().decode(TelegramLinkTokenResponse.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 503:
            throw APIError.serverErrorWithBody(503, "Telegram linking is temporarily unavailable. Please try again in a few minutes.")
        default:
            let responseString = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseString)
        }
    }

    func getTelegramLinkStatus(token: String) async throws -> TelegramLinkStatusResponse {
        var components = URLComponents(string: "\(baseURL)/api/telegram/link-status")
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try APIService.makeDecoder().decode(TelegramLinkStatusResponse.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        default:
            let responseString = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverErrorWithBody(httpResponse.statusCode, responseString)
        }
    }
}
