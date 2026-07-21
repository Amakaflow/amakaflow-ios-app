//
//  SocialImportFailure.swift
//  AmakaFlow
//
//  AMA-2285: typed failure model for social import (auth / parse / network).
//  AMA-2297: honest 403 Pro-tier messaging — never silent bookmark fallthrough.
//  AMA-2308: honest −1009 copy + transport diagnostics (never bare "No internet").
//  Failures must surface clear recoverable copy in ≤3s — never crash.
//

import Foundation
import os.log

private let socialImportTransportLogger = Logger(
    subsystem: "com.myamaka.AmakaFlowCompanion",
    category: "SocialImportTransport"
)

/// Recoverable failure categories for social → library import.
enum SocialImportFailure: Error, Equatable {
    /// Not signed in / session expired — fail fast before network.
    case auth(message: String)
    /// Subscription / tier gate (e.g. Instagram Pro required).
    case tier(message: String)
    /// Ingestor/mapper could not understand the content (4xx parse).
    case parse(message: String)
    /// Offline, timeout, or transport failure.
    case network(message: String)

    /// Short title for alerts / banners.
    var title: String {
        switch self {
        case .auth: return "Sign in required"
        case .tier: return "Pro required"
        case .parse: return "Couldn't parse workout"
        case .network: return "Network error"
        }
    }

    /// User-facing body — what failed + why.
    var userMessage: String {
        switch self {
        case .auth(let message), .tier(let message), .parse(let message), .network(let message):
            return message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .auth, .tier: return false
        case .parse: return true
        case .network: return true
        }
    }

    /// Map API / URL / CTA errors into a social-import failure category.
    /// Returns nil when the underlying request was cancelled (superseded load / dismiss).
    static func map(_ error: Error) -> SocialImportFailure? {
        if CTAError.isCancellation(error) {
            return nil
        }

        if let failure = error as? SocialImportFailure {
            return failure
        }

        if let cta = error as? CTAError {
            return mapCTA(cta)
        }

        if let api = error as? APIError {
            return mapCTA(CTAError.map(api))
        }

        if let annotated = error as? AnnotatedAPIError {
            return mapCTA(CTAError.map(annotated))
        }

        if let urlError = error as? URLError {
            return .network(message: networkMessage(for: urlError.code))
        }

        let description = error.localizedDescription
        if description.lowercased().contains("sign") || description.lowercased().contains("auth") {
            return .auth(message: description)
        }
        return .parse(message: description.isEmpty ? "Import failed. Try again or edit manually." : description)
    }

    private static func mapCTA(_ error: CTAError) -> SocialImportFailure {
        switch error {
        case .unauthenticated:
            return .auth(message: "Open AmakaFlow and sign in, then try importing again.")
        case .network(let code, _):
            return .network(message: networkMessage(for: code))
        case .decoding(let description, _):
            return .parse(message: "Couldn't read the workout response. \(description.prefix(120))")
        case .http(let status, let body, _):
            return mapHTTP(status: status, body: body)
        case .lyingSuccess(let message, let errorCode, _):
            let base = message ?? "Server reported failure"
            if let errorCode { return .parse(message: "\(base) (\(errorCode))") }
            return .parse(message: base)
        case .unknown(let description, _):
            return .parse(message: description)
        }
    }

    private static func mapHTTP(status: Int, body: String?) -> SocialImportFailure {
        if status == 401 {
            return .auth(message: "Session expired. Sign in again, then retry.")
        }
        if status == 403 {
            let detail = body.flatMap { CTAError.extractField("detail", from: $0) }
                ?? body.map { String($0.prefix(200)) }
            if let detail, looksLikeTierGate(detail) {
                return .tier(message: detail)
            }
            return .parse(message: detail ?? "Import was forbidden. Try again or edit manually.")
        }
        if status == 400 || status == 422 {
            let detail = body.flatMap { formatValidationDetail(from: $0) }
                ?? "That content couldn't be turned into a workout."
            return .parse(message: detail)
        }
        if status >= 500 {
            return .network(message: "Server error (\(status)). Try again in a moment.")
        }
        return .parse(message: body.map { String($0.prefix(160)) } ?? "Import failed (HTTP \(status)).")
    }

    private static func looksLikeTierGate(_ detail: String) -> Bool {
        let lowered = detail.lowercased()
        // Prefer entitlement phrases — avoid matching bare "pro" inside unrelated 403s.
        let phrases = [
            "pro or trainer",
            "requires a pro",
            "requires pro",
            "pro subscription",
            "trainer subscription",
            "subscription required",
            "upgrade to pro",
            "tier gate",
            "billing"
        ]
        if phrases.contains(where: { lowered.contains($0) }) {
            return true
        }
        // Word-boundary checks for standalone entitlement tokens.
        let tokens = ["subscription", "trainer", "tier"]
        return tokens.contains { token in
            lowered.range(of: #"\b\#(token)\b"#, options: .regularExpression) != nil
        }
    }

    /// FastAPI/Pydantic validation bodies use `detail: [{loc, msg}]` — not a plain string.
    private static func formatValidationDetail(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body.isEmpty ? nil : String(body.prefix(160))
        }

        if let detail = object["detail"] as? String, !detail.isEmpty {
            return detail
        }

        if let errors = object["detail"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { error -> String? in
                let msg = error["msg"] as? String
                let locParts = (error["loc"] as? [Any])?
                    .dropFirst()
                    .map { String(describing: $0) }
                if let locParts, !locParts.isEmpty, let msg {
                    return "\(locParts.joined(separator: ".")): \(msg)"
                }
                return msg
            }
            if !messages.isEmpty {
                return messages.joined(separator: "; ")
            }
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }

        return body.isEmpty ? nil : String(body.prefix(160))
    }

    private static func networkMessage(for code: URLError.Code) -> String {
        switch code {
        case .cancelled:
            return "Import was interrupted. Retry if the workout didn't appear."
        case .notConnectedToInternet:
            // AMA-2308: −1009 means CFNetwork could not start the request
            // (DNS/routing/policy) — Wi‑Fi icon can still look fine.
            return "Can't reach the import service (−1009). Wi‑Fi may still show connected — open https://workout-ingestor-api.staging.amakaflow.com/docs in Safari, then retry."
        case .networkConnectionLost:
            return "Connection dropped mid-import (−1005). Retry — if it keeps failing, check VPN/Private Relay."
        case .dataNotAllowed:
            return "Cellular data is blocked for AmakaFlow (−1020). Enable Cellular Data for this app (or join Wi‑Fi), then retry."
        case .timedOut:
            return "The request timed out (−1001). Retry — import should fail fast, not hang."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return "Couldn't reach the import service (\(code.rawValue)). Retry shortly."
        default:
            return "Network error (\(code.rawValue)). Retry when the path is clear."
        }
    }
}

// MARK: - AMA-2308 transport diagnostics

enum SocialImportTransportDiagnostics {
    /// Record structured tags for dogfood — Console + Sentry.
    /// Call from `@MainActor` import paths before mapping to UI failure.
    @MainActor
    static func record(
        _ error: Error,
        operation: String,
        intendedURL: String? = nil
    ) {
        if CTAError.isCancellation(error) { return }

        let urlError = Self.extractURLError(from: error)
        let codeRaw = urlError.map { String($0.code.rawValue) } ?? "none"
        let failingURL =
            urlError?.failingURL?.absoluteString
            ?? intendedURL
            ?? "unknown"
        let environment = AppEnvironment.current.rawValue
        let ingestor = AppEnvironment.current.ingestorAPIURL

        socialImportTransportLogger.error(
            """
            social_import_transport_fail op=\(operation, privacy: .public) \
            url_error_code=\(codeRaw, privacy: .public) \
            failing_url=\(failingURL, privacy: .public) \
            app_environment=\(environment, privacy: .public) \
            ingestor_base=\(ingestor, privacy: .public) \
            error=\(String(describing: error), privacy: .public)
            """
        )

        SentryService.shared.captureSocialImportTransport(
            error: error,
            urlErrorCode: urlError.map(\.code.rawValue),
            failingURL: failingURL,
            appEnvironment: environment,
            ingestorBase: ingestor,
            operation: operation
        )
    }

    private static func extractURLError(from error: Error) -> URLError? {
        if let urlError = error as? URLError {
            return urlError
        }
        if let annotated = error as? AnnotatedAPIError {
            return extractURLError(from: annotated.underlying)
        }
        if let api = error as? APIError {
            switch api {
            case .network(let underlying), .networkError(let underlying):
                return extractURLError(from: underlying)
            default:
                return nil
            }
        }
        if let cta = error as? CTAError, case .network(let code, _) = cta {
            return URLError(code)
        }
        return nil
    }
}
