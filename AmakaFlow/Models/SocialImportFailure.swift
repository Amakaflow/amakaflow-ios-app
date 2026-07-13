//
//  SocialImportFailure.swift
//  AmakaFlow
//
//  AMA-2285: typed failure model for social import (auth / parse / network).
//  Failures must surface clear recoverable copy in ≤3s — never crash.
//

import Foundation

/// Recoverable failure categories for social → library import.
enum SocialImportFailure: Error, Equatable {
    /// Not signed in / session expired — fail fast before network.
    case auth(message: String)
    /// Ingestor/mapper could not understand the content (4xx parse).
    case parse(message: String)
    /// Offline, timeout, or transport failure.
    case network(message: String)

    /// Short title for alerts / banners.
    var title: String {
        switch self {
        case .auth: return "Sign in required"
        case .parse: return "Couldn't parse workout"
        case .network: return "Network error"
        }
    }

    /// User-facing body — what failed + why.
    var userMessage: String {
        switch self {
        case .auth(let message), .parse(let message), .network(let message):
            return message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .auth: return false
        case .parse: return true
        case .network: return true
        }
    }

    /// Map API / URL / CTA errors into a social-import failure category.
    static func map(_ error: Error) -> SocialImportFailure {
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
            if status == 401 || status == 403 {
                return .auth(message: "Session expired. Sign in again, then retry.")
            }
            if status == 400 || status == 422 {
                let detail = body.flatMap { CTAError.extractField("detail", from: $0) }
                    ?? body.map { String($0.prefix(160)) }
                    ?? "That content couldn't be turned into a workout."
                return .parse(message: detail)
            }
            if status >= 500 {
                return .network(message: "Server error (\(status)). Try again in a moment.")
            }
            return .parse(message: body.map { String($0.prefix(160)) } ?? "Import failed (HTTP \(status)).")
        case .lyingSuccess(let message, let errorCode, _):
            let base = message ?? "Server reported failure"
            if let errorCode { return .parse(message: "\(base) (\(errorCode))") }
            return .parse(message: base)
        case .unknown(let description, _):
            return .parse(message: description)
        }
    }

    private static func networkMessage(for code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "No internet connection. Check connectivity and retry."
        case .timedOut:
            return "The request timed out. Retry — import should fail fast, not hang."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return "Couldn't reach the import service. Retry shortly."
        default:
            return "Network error (\(code.rawValue)). Retry when you're back online."
        }
    }
}
