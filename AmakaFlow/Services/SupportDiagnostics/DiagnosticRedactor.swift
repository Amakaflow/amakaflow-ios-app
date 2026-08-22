import CryptoKit
import Foundation

nonisolated struct DiagnosticRedactor: Sendable {
    static let omittedBodyMessage = "Diagnostic body omitted from diagnostics"
    static let omittedAPIResponseMessage = omittedBodyMessage

    private static let redacted = "[REDACTED]"
    private static let redactedEmail = "[REDACTED_EMAIL]"
    private static let redactedQuery = "[REDACTED_QUERY]"
    private static let maxValueLength = 256
    private static let sensitiveKeyFragments = [
        "authorization",
        "token",
        "secret",
        "cookie",
        "password",
        "email",
        "location",
        "health",
        "sample",
        "body"
    ]

    func redact(
        category: DiagnosticEventCategory,
        severity: DiagnosticEventSeverity,
        name: String,
        displayTitle: String? = nil,
        message: String,
        metadata: [String: String] = [:],
        requestID: String? = nil,
        sentryEventID: String? = nil,
        sentryTraceID: String? = nil,
        accountIdentifier: String? = nil,
        timestamp: Date = Date()
    ) -> DiagnosticEvent {
        let sanitizedMetadata = sanitizeMetadata(metadata, category: category)
        return DiagnosticEvent(
            timestamp: timestamp,
            severity: severity,
            category: category,
            name: sanitizeIdentifier(sanitizeText(name), fallback: "diagnostic.event"),
            title: sanitizeDisplayTitle(displayTitle ?? name, fallback: name),
            message: shouldOmitDiagnosticBody(message, metadata: metadata)
                ? Self.omittedBodyMessage
                : sanitizeText(message),
            metadata: sanitizedMetadata,
            requestID: sanitizeCorrelationID(requestID ?? sanitizedMetadata["request_id"] ?? sanitizedMetadata["requestId"]),
            sentryEventID: sanitizeCorrelationID(sentryEventID ?? sanitizedMetadata["sentry_event_id"]),
            sentryTraceID: sanitizeCorrelationID(
                sentryTraceID
                    ?? sanitizedMetadata["sentry_trace_id"]
                    ?? sanitizedMetadata["trace_id"]
                    ?? sanitizedMetadata["traceId"]
            ),
            accountHash: hashAccountIdentifier(accountIdentifier)
        )
    }

    func redactLegacyEntry(_ entry: DebugLogEntry) -> DiagnosticEvent {
        let category = category(for: entry.type)
        let severity = severity(for: entry.type)
        let sanitizedMetadata = sanitizeMetadata(entry.metadata ?? [:], category: category)
        let omitLegacyBody = shouldOmitDiagnosticBody(entry.details, metadata: entry.metadata ?? [:])
        return DiagnosticEvent(
            id: entry.id,
            timestamp: entry.timestamp,
            severity: severity,
            category: category,
            name: stableEventName(for: entry.type),
            title: sanitizeDisplayTitle(entry.title, fallback: stableEventName(for: entry.type)),
            message: omitLegacyBody ? Self.omittedBodyMessage : sanitizeText(entry.details),
            metadata: sanitizedMetadata,
            requestID: sanitizeCorrelationID(sanitizedMetadata["request_id"] ?? sanitizedMetadata["requestId"]),
            sentryEventID: nil,
            sentryTraceID: sanitizeCorrelationID(sanitizedMetadata["trace_id"] ?? sanitizedMetadata["traceId"]),
            accountHash: nil
        )
    }

    func hashAccountIdentifier(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(identifier.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    func sanitizeText(_ text: String) -> String {
        var sanitized = text
        sanitized = replace(
            pattern: #"(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+/\-=]+"#,
            in: sanitized,
            with: "$1\(Self.redacted)"
        )
        sanitized = replace(
            pattern: #"(?i)(bearer\s+)[A-Za-z0-9._~+/\-=]+"#,
            in: sanitized,
            with: "$1\(Self.redacted)"
        )
        sanitized = replace(
            pattern: #"\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,}\b"#,
            in: sanitized,
            with: Self.redacted
        )
        sanitized = replace(
            pattern: #"(?i)(cookie\s*:\s*)[^\n\r]+"#,
            in: sanitized,
            with: "$1\(Self.redacted)"
        )
        sanitized = replace(
            pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            in: sanitized,
            options: [.caseInsensitive],
            with: Self.redactedEmail
        )
        sanitized = replace(
            pattern: #"https?://[^\s?#]+(?:\?[^\s#]*)?(?:#[^\s]*)?"#,
            in: sanitized
        ) { match in
            guard let url = URL(string: match), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return match.contains("?") ? String(match.prefix { $0 != "?" }) + "?\(Self.redactedQuery)" : match
            }
            if components.query != nil {
                components.query = Self.redactedQuery
            }
            return components.string ?? "\(url.scheme ?? "https")://\(url.host ?? "unknown")?\(Self.redactedQuery)"
        }
        sanitized = replace(
            pattern: #"(/[A-Za-z0-9._~%!$&'()*+,;=:@/-]+)\?[^\s#]+"#,
            in: sanitized
        ) { match in
            guard let queryStart = match.firstIndex(of: "?") else { return match }
            return "\(match[..<queryStart])?\(Self.redactedQuery)"
        }
        sanitized = replace(
            pattern: #"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{8,}\b|\bclerk_secret_[A-Za-z0-9_-]{4,}\b|\bAKIA[0-9A-Z]{16}\b"#,
            in: sanitized,
            options: [.caseInsensitive],
            with: Self.redacted
        )
        sanitized = replace(
            pattern: #"(?i)\b(access_token|refresh_token|id_token|api_key|client_secret|password)\b\s*[:=]\s*"?[^",\s}]+"?"#,
            in: sanitized
        ) { match in
            guard let separator = match.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                return Self.redacted
            }
            return "\(match[..<separator])\(match[separator]) \(Self.redacted)"
        }
        return sanitized
    }
}

private extension DiagnosticRedactor {
    func sanitizeMetadata(
        _ metadata: [String: String],
        category: DiagnosticEventCategory
    ) -> [String: String] {
        let allowedKeys = allowedMetadataKeys(for: category)
        var sanitized: [String: String] = [:]
        for (key, value) in metadata {
            guard allowedKeys.contains(key),
                  !isSensitiveKey(key)
            else { continue }
            sanitized[key] = sanitizeMetadataValue(value, key: key)
        }
        return sanitized
    }

    private func sanitizeMetadataValue(_ value: String, key: String) -> String {
        let sanitized: String
        if key == "Endpoint" || key == "endpoint" || key == "path" {
            sanitized = normalizedPath(value)
        } else {
            sanitized = sanitizeText(value)
        }
        return String(sanitized.prefix(Self.maxValueLength))
    }

    private func allowedMetadataKeys(for category: DiagnosticEventCategory) -> Set<String> {
        let correlation = Set(["request_id", "requestId", "trace_id", "traceId", "sentry_event_id", "sentry_trace_id"])
        switch category {
        case .api:
            return correlation.union([
                "Endpoint",
                "endpoint",
                "path",
                "Method",
                "method",
                "Status",
                "status",
                "duration_ms",
                "retry_count",
                "response_size",
                "server_request_id"
            ])
        case .auth, .network, .sync, .completion, .watch, .healthKit, .storage, .appLifecycle, .operatorAction, .general:
            return correlation.union(["Context", "context", "WorkoutID", "workout_id", "action", "outcome", "error_code"])
        }
    }

    private func isSensitiveKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        if ["response", "request", "raw_response", "response_body", "request_body"].contains(lowercased) {
            return true
        }
        return Self.sensitiveKeyFragments.contains { lowercased.contains($0) }
    }

    private func sanitizeDisplayTitle(_ value: String, fallback: String) -> String {
        let sanitized = sanitizeText(value)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((sanitized.nilIfEmpty ?? fallback).prefix(Self.maxValueLength))
    }

    private func shouldOmitDiagnosticBody(
        _ message: String,
        metadata: [String: String]
    ) -> Bool {
        hasBodySignal(in: metadata) || isBodyLike(message)
    }

    private func hasBodySignal(in metadata: [String: String]) -> Bool {
        metadata.keys.contains { key in
            let lowercased = key.lowercased()
            return [
                "response",
                "request",
                "raw_response",
                "response_body",
                "request_body",
                "body",
                "json",
                "payload",
                "profile",
                "customer",
                "health",
                "location"
            ].contains(lowercased)
        }
    }

    private func isBodyLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return true
        }
        let lowercased = trimmed.lowercased()
        return [
            "access_token",
            "refresh_token",
            "id_token",
            "profile",
            "customer",
            "health",
            "location",
            "payload",
            "response_body",
            "request_body"
        ].contains { lowercased.contains($0) }
    }

    private func normalizedPath(_ value: String) -> String {
        if let components = URLComponents(string: value), let path = components.path.nilIfEmpty {
            return path
        }
        if let question = value.firstIndex(of: "?") {
            return String(value[..<question]).nilIfEmpty ?? "/"
        }
        return value.nilIfEmpty ?? "/"
    }

    private func sanitizeIdentifier(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "."
        }).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return sanitized.nilIfEmpty ?? fallback
    }

    private func sanitizeCorrelationID(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".:_-"))
        let sanitized = String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        })
        return String(sanitized.prefix(96)).nilIfEmpty
    }

    private func category(for type: DebugLogType) -> DiagnosticEventCategory {
        switch type {
        case .apiError, .apiSuccess:
            return .api
        case .watchError, .watchEvent:
            return .watch
        case .completionError:
            return .completion
        case .networkError:
            return .network
        case .authError:
            return .auth
        case .general:
            return .general
        }
    }

    private func severity(for type: DebugLogType) -> DiagnosticEventSeverity {
        switch type {
        case .apiSuccess, .watchEvent, .general:
            return .info
        case .networkError:
            return .warning
        case .apiError, .watchError, .completionError, .authError:
            return .error
        }
    }

    private func stableEventName(for type: DebugLogType) -> String {
        switch type {
        case .apiError:
            return "api.request.failed"
        case .apiSuccess:
            return "api.request.succeeded"
        case .watchError:
            return "watch.error"
        case .watchEvent:
            return "watch.event"
        case .completionError:
            return "completion.failed"
        case .networkError:
            return "network.error"
        case .authError:
            return "auth.error"
        case .general:
            return "general.event"
        }
    }

    private func replace(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [],
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private func replace(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [],
        transform: (String) -> String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let matches = expression.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
