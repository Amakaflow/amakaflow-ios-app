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
import os
import Sentry

struct APILogEvent: Equatable {
    enum Phase: String {
        case start
        case end
        case fail
    }

    let phase: Phase
    let endpoint: String
    let httpMethod: String
    let statusCode: Int?
    let durationMs: Int
    let requestId: String
    let serverRequestId: String?
    let errorType: String?
}

protocol APIObservabilityLogging: AnyObject {
    func log(_ event: APILogEvent)
}

final class DefaultAPIObservabilityLogger: APIObservabilityLogging {
    static let shared = DefaultAPIObservabilityLogger()

    private let logger = Logger(subsystem: "com.amakaflow.app", category: "network")

    private init() {}

    func log(_ event: APILogEvent) {
        let status = event.statusCode.map(String.init) ?? "none"
        let errorType = event.errorType ?? "none"
        let serverRequestId = event.serverRequestId ?? "none"

        logger.info(
            "api_call phase=\(event.phase.rawValue, privacy: .public) endpoint=\(event.endpoint, privacy: .public) httpMethod=\(event.httpMethod, privacy: .public) statusCode=\(status, privacy: .public) durationMs=\(event.durationMs, privacy: .public) requestId=\(event.requestId, privacy: .public) serverRequestId=\(serverRequestId, privacy: .public) errorType=\(errorType, privacy: .public)"
        )

        if event.phase == .fail {
            addSentryBreadcrumb(for: event, status: status, errorType: errorType)
        }

        Task { @MainActor in
            switch event.phase {
            case .start:
                break
            case .end:
                DebugLogService.shared.logAPISuccess(
                    endpoint: event.endpoint,
                    method: event.httpMethod,
                    statusCode: event.statusCode ?? 0
                )
            case .fail:
                DebugLogService.shared.logAPIError(
                    endpoint: event.endpoint,
                    method: event.httpMethod,
                    statusCode: event.statusCode,
                    response: nil,
                    error: nil,
                    requestID: event.requestId
                )
            }
        }
    }

    private func addSentryBreadcrumb(for event: APILogEvent, status: String, errorType: String) {
        let crumb = Breadcrumb(level: .error, category: "api")
        crumb.message = "\(event.httpMethod) \(event.endpoint) failed"
        crumb.data = [
            "endpoint": event.endpoint,
            "httpMethod": event.httpMethod,
            "statusCode": status,
            "durationMs": String(event.durationMs),
            "requestId": event.requestId,
            "request_id": event.requestId,
            "serverRequestId": event.serverRequestId ?? "",
            "rndr_id": event.serverRequestId ?? "",
            "errorType": errorType
        ]
        SentrySDK.addBreadcrumb(crumb)
    }
}

extension APIService {

    // MARK: - Shared JSON Decoder

    /// Create a JSONDecoder configured for our API responses
    /// Handles ISO8601 dates both with and without fractional seconds
    nonisolated static func makeDecoder() -> JSONDecoder {
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

    // MARK: - Shared Request Path (AMA-1933)

    /// Single async request primitive for repository migrations.
    ///
    /// Pattern for the remaining repository files: build a `URLRequest`, then call
    /// `request(_:decode:)`, `requestData(_:)`, or `requestVoid(_:)`. Do not call
    /// `session.data(for:)` directly from endpoint methods; this helper owns APIError
    /// mapping plus start/end/fail observability for every network call.
    func request<T: Decodable>(
        _ request: URLRequest,
        decode type: T.Type,
        decoder: JSONDecoder = APIService.makeDecoder(),
        successStatusCodes: ClosedRange<Int> = 200...299
    ) async throws -> T {
        let result = try await performRequest(request, successStatusCodes: successStatusCodes)
        do {
            let decoded = try decoder.decode(type, from: result.data)
            logAPIEvent(
                phase: .end,
                endpoint: result.endpoint,
                method: result.method,
                statusCode: result.statusCode,
                startedAt: result.startedAt,
                requestId: result.requestId,
                serverRequestId: result.serverRequestId,
                error: nil
            )
            return decoded
        } catch {
            let apiError = APIError.decoding(underlying: error)
            logAPIEvent(
                phase: .fail,
                endpoint: result.endpoint,
                method: result.method,
                statusCode: result.statusCode,
                startedAt: result.startedAt,
                requestId: result.requestId,
                serverRequestId: result.serverRequestId,
                error: apiError
            )
            throw apiError
        }
    }

    func requestData(
        _ request: URLRequest,
        successStatusCodes: ClosedRange<Int> = 200...299
    ) async throws -> Data {
        let result = try await performRequest(request, successStatusCodes: successStatusCodes)
        logAPIEvent(
            phase: .end,
            endpoint: result.endpoint,
            method: result.method,
            statusCode: result.statusCode,
            startedAt: result.startedAt,
            requestId: result.requestId,
            serverRequestId: result.serverRequestId,
            error: nil
        )
        return result.data
    }

    func requestVoid(
        _ request: URLRequest,
        successStatusCodes: ClosedRange<Int> = 200...299
    ) async throws {
        _ = try await requestData(request, successStatusCodes: successStatusCodes)
    }

    func makeAPIRequest(
        baseURL: String? = nil,
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Data? = nil,
        headers: [String: String]? = nil
    ) async throws -> URLRequest {
        let root = baseURL ?? self.baseURL
        guard var components = URLComponents(string: root + path) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let headers {
            request.allHTTPHeaderFields = headers
        } else {
            request.allHTTPHeaderFields = await makeAuthHeaders()
        }
        request.httpBody = body
        return request
    }

    func encodeJSONBody<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            // Don't swallow context: encoding failures are programmer errors and
            // must be visible (CLAUDE.md: no silent failures / AMA-1933).
            Logger(subsystem: "com.amakaflow.app", category: "network")
                .error("JSON body encoding failed for \(String(describing: T.self), privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw APIError.unknown
        }
    }

    private struct RequestResult {
        let data: Data
        let endpoint: String
        let method: String
        let statusCode: Int
        let startedAt: Date
        let requestId: String
        let serverRequestId: String?
    }

    private func performRequest(
        _ request: URLRequest,
        successStatusCodes: ClosedRange<Int>
    ) async throws -> RequestResult {
        let endpoint = Self.sanitizedEndpoint(from: request.url)
        let method = request.httpMethod ?? "GET"
        var request = request
        let startedAt = Date()
        let generatedRequestId = request.value(forHTTPHeaderField: "X-Request-ID") ?? UUID().uuidString
        request.setValue(generatedRequestId, forHTTPHeaderField: "X-Request-ID")

        logAPIEvent(
            phase: .start,
            endpoint: endpoint,
            method: method,
            statusCode: nil,
            startedAt: startedAt,
            requestId: generatedRequestId,
            serverRequestId: nil,
            error: nil
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                let apiError = APIError.unknown
                logAPIEvent(
                    phase: .fail,
                    endpoint: endpoint,
                    method: method,
                    statusCode: nil,
                    startedAt: startedAt,
                    requestId: generatedRequestId,
                    serverRequestId: nil,
                    error: apiError
                )
                throw apiError
            }

            let rndrId = httpResponse.value(forHTTPHeaderField: "Rndr-Id")
            let serverRequestId = rndrId == generatedRequestId ? nil : rndrId
            let statusCode = httpResponse.statusCode
            guard successStatusCodes.contains(statusCode) else {
                let apiError = Self.mapStatusCode(statusCode)
                logAPIEvent(
                    phase: .fail,
                    endpoint: endpoint,
                    method: method,
                    statusCode: statusCode,
                    startedAt: startedAt,
                    requestId: generatedRequestId,
                    serverRequestId: serverRequestId,
                    error: apiError
                )
                throw apiError
            }

            return RequestResult(
                data: data,
                endpoint: endpoint,
                method: method,
                statusCode: statusCode,
                startedAt: startedAt,
                requestId: generatedRequestId,
                serverRequestId: serverRequestId
            )
        } catch let apiError as APIError {
            throw apiError
        } catch {
            let apiError = APIError.network(underlying: error)
            logAPIEvent(
                phase: .fail,
                endpoint: endpoint,
                method: method,
                statusCode: nil,
                startedAt: startedAt,
                requestId: generatedRequestId,
                serverRequestId: nil,
                error: apiError
            )
            throw apiError
        }
    }

    private func logAPIEvent(
        phase: APILogEvent.Phase,
        endpoint: String,
        method: String,
        statusCode: Int?,
        startedAt: Date,
        requestId: String,
        serverRequestId: String?,
        error: APIError?
    ) {
        let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        observabilityLogger.log(APILogEvent(
            phase: phase,
            endpoint: endpoint,
            httpMethod: method,
            statusCode: statusCode,
            durationMs: durationMs,
            requestId: requestId,
            serverRequestId: serverRequestId,
            errorType: error?.sanitizedErrorType
        ))
    }

    static func sanitizedEndpoint(from url: URL?) -> String {
        guard let url = url else { return "unknown" }
        return url.path.isEmpty ? "/" : url.path
    }

    static func mapStatusCode(_ statusCode: Int) -> APIError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 404:
            return .notFound
        default:
            return .server(status: statusCode)
        }
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
            let apiError = error ?? APIError.server(status: statusCode ?? 0)
            SentryService.shared.captureAPIError(
                apiError,
                endpoint: "\(method) \(endpoint)",
                statusCode: statusCode,
                responseBody: response
            )
        }
    }
}
