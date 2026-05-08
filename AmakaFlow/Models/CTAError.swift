//
//  CTAError.swift
//  AmakaFlow
//
//  AMA-1803 P0: a typed failure model for primary CTA network calls.
//
//  Why this exists: AMA-1798/1799/1800 shipped iOS-rejecting bugs to staging
//  because the iOS UI declared "Saved!" while the network call silently failed
//  or returned HTTP 200 with `success:false`. This type forces every CTA's
//  failure path through one shape that view-models can publish and views can
//  render — no more `error.localizedDescription` strings that drop error_code
//  and request_id, the two fields ops needs to correlate with AMA-1805's
//  Sentry tags.
//

import Foundation

/// A canonical failure shape for primary CTA network actions.
///
/// Every variant carries `requestId` (from the failing response's
/// `X-Request-ID` header) so the user-facing "Report" button can write a
/// breadcrumb that joins back to AMA-1805's server-side capture.
public enum CTAError: Error, Equatable {
    /// `URLError` — no network, timeout, dropped connection.
    /// User UI: shows toast + Retry affordance.
    case network(code: URLError.Code, requestId: String? = nil)

    /// HTTP 4xx / 5xx with a non-`success:false` body.
    /// User UI: toast + Retry on 5xx, no Retry on 4xx.
    case http(status: Int, body: String?, requestId: String? = nil)

    /// HTTP 200 / 201 with body `{"success": false, ...}` — the
    /// "lying success" pattern that hid AMA-1798 / 1799 / 1800.
    /// User UI: toast (no Retry — server processed it deliberately).
    case lyingSuccess(message: String?, errorCode: String?, requestId: String? = nil)

    /// JSON decoding failed — server returned an unexpected shape.
    /// User UI: toast + Report button (this is almost always a bug).
    case decoding(description: String, requestId: String? = nil)

    /// Auth dependency rejected the request.
    /// User UI: route to sign-in flow, NOT a toast.
    case unauthenticated(requestId: String? = nil)

    /// Unknown / unmapped — keep around so CTAError can be the SOLE
    /// failure shape, never `Error?` falls through to a stringly path.
    case unknown(description: String, requestId: String? = nil)
}

// MARK: - User-facing copy

public extension CTAError {
    /// Short label naming the action that failed. Pass when constructing
    /// the toast — e.g. `actionTitle: "Couldn't save workout"`.
    /// The CTAError itself is action-agnostic; copy is the View's job.

    /// Body shown under the action title.
    var userMessage: String {
        switch self {
        case .network(let code, _):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection."
            case .timedOut:
                return "The request timed out."
            default:
                return "Network error (\(code.rawValue))."
            }
        case .http(let status, let body, _):
            if let body = body, !body.isEmpty {
                let trimmed = body.prefix(160)
                return "Server error \(status): \(trimmed)"
            }
            return "Server error \(status)."
        case .lyingSuccess(let message, let errorCode, _):
            if let errorCode = errorCode, let message = message {
                return "\(message) (\(errorCode))"
            }
            return message ?? "Server reported failure."
        case .decoding(let description, _):
            return "Couldn't read the server response. \(description.prefix(120))"
        case .unauthenticated:
            return "You've been signed out. Please sign in again."
        case .unknown(let description, _):
            return description
        }
    }

    /// Whether the toast should offer a Retry button. Network +
    /// transient 5xx are retryable; 4xx and decoding errors aren't.
    var isRetryable: Bool {
        switch self {
        case .network: return true
        case .http(let status, _, _): return status >= 500
        case .lyingSuccess, .decoding, .unauthenticated, .unknown: return false
        }
    }

    /// Stable code used as a Sentry tag. Pairs with AMA-1805's
    /// server-side tags for correlation in alerts and logs.
    var sentryFailureCode: String {
        switch self {
        case .network: return "network"
        case .http(let status, _, _): return "http_\(status)"
        case .lyingSuccess: return "lying_success_200"
        case .decoding: return "decoding"
        case .unauthenticated: return "unauthenticated"
        case .unknown: return "unknown"
        }
    }

    /// The X-Request-ID (if any) from the response that caused the
    /// failure. Pulled into Sentry tags + the Report-button payload.
    var requestId: String? {
        switch self {
        case .network(_, let id),
             .http(_, _, let id),
             .lyingSuccess(_, _, let id),
             .decoding(_, let id),
             .unauthenticated(let id),
             .unknown(_, let id):
            return id
        }
    }
}

// MARK: - Mapping from APIError / URLError

public extension CTAError {
    /// Translate an underlying error from APIService into a CTAError.
    /// Centralised so view-models never see the raw error type.
    static func map(_ error: Error, requestId: String? = nil) -> CTAError {
        // AMA-271 detects success:false in the response body and rethrows
        // as APIError.serverErrorWithBody(200, body). Pull that apart.
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return .unauthenticated(requestId: requestId)
            case .invalidURL, .invalidResponse, .notImplemented, .notFound:
                return .unknown(
                    description: apiError.errorDescription ?? "Unexpected error",
                    requestId: requestId
                )
            case .networkError(let underlying):
                if let urlError = underlying as? URLError {
                    return .network(code: urlError.code, requestId: requestId)
                }
                return .unknown(
                    description: underlying.localizedDescription,
                    requestId: requestId
                )
            case .decodingError(let underlying):
                return .decoding(
                    description: underlying.localizedDescription,
                    requestId: requestId
                )
            case .serverError(let code):
                return .http(status: code, body: nil, requestId: requestId)
            case .serverErrorWithBody(let code, let body):
                // AMA-271: for 200 responses with `success: false`,
                // APIService re-throws this with status=200. Detect the
                // lying-success path and surface it as such; the toast
                // copy + Retry behaviour differ from a real HTTP error.
                if (200...299).contains(code), body.contains("\"success\":false") || body.contains("\"success\": false") {
                    let message = Self.extractField("message", from: body)
                    let errorCode = Self.extractField("error_code", from: body)
                    return .lyingSuccess(message: message, errorCode: errorCode, requestId: requestId)
                }
                return .http(status: code, body: body, requestId: requestId)
            }
        }

        if let urlError = error as? URLError {
            return .network(code: urlError.code, requestId: requestId)
        }

        return .unknown(description: error.localizedDescription, requestId: requestId)
    }

    /// Tiny, dependency-free string extractor for `"<key>": "<value>"`
    /// from a JSON body. Not a full parser — we only need the two
    /// fields the AMA-1805 alert template emits. Falls back to nil
    /// silently so a malformed body doesn't double-fault.
    static func extractField(_ key: String, from body: String) -> String? {
        let needle = "\"\(key)\""
        guard let keyRange = body.range(of: needle) else { return nil }
        let after = body[keyRange.upperBound...]
        // Skip optional whitespace + colon + optional whitespace + opening quote.
        guard let colon = after.firstIndex(of: ":") else { return nil }
        let afterColon = after[after.index(after: colon)...]
        guard let openQuote = afterColon.firstIndex(of: "\"") else { return nil }
        let valueStart = afterColon.index(after: openQuote)
        // Find closing quote that isn't escaped. Cheap version: ignore
        // backslash-escaped quotes since the alert payload doesn't include them.
        guard let closeQuote = afterColon[valueStart...].firstIndex(of: "\"") else { return nil }
        return String(afterColon[valueStart..<closeQuote])
    }
}
