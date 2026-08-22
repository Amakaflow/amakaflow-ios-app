import Foundation

nonisolated struct DiagnosticRedactionPolicy: Sendable {
    private let sensitiveKeyFragments = [
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

    func sanitizeMetadata(
        _ metadata: [String: String],
        category: DiagnosticEventCategory,
        textSanitizer: DiagnosticTextSanitizer
    ) -> [String: String] {
        let allowedKeys = allowedMetadataKeys(for: category)
        var sanitized: [String: String] = [:]
        for (key, value) in metadata {
            guard allowedKeys.contains(key),
                  !isSensitiveKey(key)
            else { continue }
            sanitized[key] = sanitizeMetadataValue(value, key: key, textSanitizer: textSanitizer)
        }
        return sanitized
    }

    func sanitizeDisplayTitle(
        _ value: String,
        fallback: String,
        textSanitizer: DiagnosticTextSanitizer
    ) -> String {
        let sanitized = textSanitizer.sanitize(value)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((nilIfEmpty(sanitized) ?? fallback).prefix(DiagnosticRedactor.maxValueLength))
    }

    func shouldOmitDiagnosticBody(
        _ message: String,
        metadata: [String: String]
    ) -> Bool {
        hasBodySignal(in: metadata) || isBodyLike(message)
    }

    func sanitizeIdentifier(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "."
        }).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return nilIfEmpty(sanitized) ?? fallback
    }

    func sanitizeCorrelationID(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".:_-"))
        let sanitized = String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        })
        return nilIfEmpty(String(sanitized.prefix(96)))
    }

    private func sanitizeMetadataValue(
        _ value: String,
        key: String,
        textSanitizer: DiagnosticTextSanitizer
    ) -> String {
        let sanitized: String
        if key == "Endpoint" || key == "endpoint" || key == "path" {
            sanitized = normalizedPath(value)
        } else {
            sanitized = textSanitizer.sanitize(value)
        }
        return String(sanitized.prefix(DiagnosticRedactor.maxValueLength))
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
        return sensitiveKeyFragments.contains { lowercased.contains($0) }
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
        if let components = URLComponents(string: value), let path = nilIfEmpty(components.path) {
            return path
        }
        if let question = value.firstIndex(of: "?") {
            return nilIfEmpty(String(value[..<question])) ?? "/"
        }
        return nilIfEmpty(value) ?? "/"
    }

    private func nilIfEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
