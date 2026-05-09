//
//  APITransport.swift
//  AmakaFlow
//
//  AMA-1828: shared transport-layer concerns extracted from APIService.swift
//  during the per-domain repository split. Holds decoder/encoder factories
//  and the centralized error logging + Sentry annotation helper used by
//  every domain extension. Auth header helpers, the URLSession instance,
//  and the baseURL/bffURL accessors continue to live on the APIService
//  class itself (in APIService.swift) so the existing
//  `APIService: APIServiceProviding` conformance keeps working without
//  touching the 19 call sites that reference `APIService.shared.foo()`.
//

import Foundation
import Sentry

extension APIService {

    // MARK: - Shared JSON Decoder

    /// Create a JSONDecoder configured for our API responses
    /// Handles ISO8601 dates both with and without fractional seconds
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first (e.g., "2026-01-02T02:41:21.295+00:00")
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractional.date(from: dateString) {
                return date
            }

            // Fall back to standard ISO8601 (e.g., "2025-01-01T10:00:00Z")
            let formatterStandard = ISO8601DateFormatter()
            formatterStandard.formatOptions = [.withInternetDateTime]
            if let date = formatterStandard.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }

    // MARK: - Error Logging Helper

    func logError(endpoint: String, method: String, statusCode: Int?, response: String?, error: Error?) {
        Task { @MainActor in
            // Log to debug service
            DebugLogService.shared.logAPIError(
                endpoint: endpoint,
                method: method,
                statusCode: statusCode,
                response: response,
                error: error
            )

            // Capture to Sentry (AMA-225)
            let apiError = error ?? APIError.serverError(statusCode ?? 0)
            SentryService.shared.captureAPIError(
                apiError,
                endpoint: "\(method) \(endpoint)",
                statusCode: statusCode,
                responseBody: response
            )
        }
    }
}
