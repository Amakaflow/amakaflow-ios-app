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
//    POST  /v1/messaging/telegram/setup
//    GET   /v1/messaging/telegram/status?token=…
//

import Foundation

extension APIService {

    // MARK: - Telegram Linking

    func mintTelegramLinkToken() async throws -> TelegramLinkTokenResponse {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/messaging/telegram/setup",
            method: "POST"
        )
        let response = try await self.request(
            request,
            decode: Components.Schemas.TelegramSetupResponse.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
        return TelegramLinkTokenResponse(response)
    }

    func getTelegramLinkStatus(token: String) async throws -> TelegramLinkStatusResponse {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/messaging/telegram/status",
            queryItems: [URLQueryItem(name: "token", value: token)],
            method: "GET"
        )
        let response = try await self.request(
            request,
            decode: Components.Schemas.TelegramStatusResponse.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
        return TelegramLinkStatusResponse(response)
    }
}

private extension TelegramLinkTokenResponse {
    init(_ response: Components.Schemas.TelegramSetupResponse) {
        self.init(
            token: response.token,
            deepLink: response.deepLink,
            nativeLink: response.nativeLink,
            expiresInSeconds: response.expiresInSeconds
        )
    }
}

private extension TelegramLinkStatusResponse {
    init(_ response: Components.Schemas.TelegramStatusResponse) {
        self.init(
            linked: response.linked,
            telegramId: nil,
            telegramIdHash: response.telegramIdHash,
            usedAt: nil
        )
    }
}
