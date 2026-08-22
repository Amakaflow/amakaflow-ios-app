import CryptoKit
import Foundation

nonisolated struct DiagnosticRedactor: Sendable {
    static let omittedBodyMessage = "Diagnostic body omitted from diagnostics"
    static let omittedAPIResponseMessage = omittedBodyMessage

    static let redacted = "[REDACTED]"
    static let redactedEmail = "[REDACTED_EMAIL]"
    static let redactedQuery = "[REDACTED_QUERY]"
    static let maxValueLength = 256

    private let textSanitizer = DiagnosticTextSanitizer()
    private let policy = DiagnosticRedactionPolicy()
    private let legacyMapping = DiagnosticLegacyEventMapping()

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
        let sanitizedMetadata = policy.sanitizeMetadata(metadata, category: category, textSanitizer: textSanitizer)
        return DiagnosticEvent(
            timestamp: timestamp,
            severity: severity,
            category: category,
            name: policy.sanitizeIdentifier(sanitizeText(name), fallback: "diagnostic.event"),
            title: policy.sanitizeDisplayTitle(displayTitle ?? name, fallback: name, textSanitizer: textSanitizer),
            message: policy.shouldOmitDiagnosticBody(message, metadata: metadata)
                ? Self.omittedBodyMessage
                : sanitizeText(message),
            metadata: sanitizedMetadata,
            requestID: policy.sanitizeCorrelationID(
                requestID ?? sanitizedMetadata["request_id"] ?? sanitizedMetadata["requestId"]
            ),
            sentryEventID: policy.sanitizeCorrelationID(sentryEventID ?? sanitizedMetadata["sentry_event_id"]),
            sentryTraceID: policy.sanitizeCorrelationID(
                sentryTraceID
                    ?? sanitizedMetadata["sentry_trace_id"]
                    ?? sanitizedMetadata["trace_id"]
                    ?? sanitizedMetadata["traceId"]
            ),
            accountHash: hashAccountIdentifier(accountIdentifier)
        )
    }

    func redactLegacyEntry(_ entry: DebugLogEntry) -> DiagnosticEvent {
        let category = legacyMapping.category(for: entry.type)
        let sanitizedMetadata = policy.sanitizeMetadata(
            entry.metadata ?? [:],
            category: category,
            textSanitizer: textSanitizer
        )
        let omitLegacyBody = policy.shouldOmitDiagnosticBody(entry.details, metadata: entry.metadata ?? [:])
        return DiagnosticEvent(
            id: entry.id,
            timestamp: entry.timestamp,
            severity: legacyMapping.severity(for: entry.type),
            category: category,
            name: legacyMapping.stableEventName(for: entry.type),
            title: policy.sanitizeDisplayTitle(
                entry.title,
                fallback: legacyMapping.stableEventName(for: entry.type),
                textSanitizer: textSanitizer
            ),
            message: omitLegacyBody ? Self.omittedBodyMessage : sanitizeText(entry.details),
            metadata: sanitizedMetadata,
            requestID: policy.sanitizeCorrelationID(sanitizedMetadata["request_id"] ?? sanitizedMetadata["requestId"]),
            sentryEventID: nil,
            sentryTraceID: policy.sanitizeCorrelationID(sanitizedMetadata["trace_id"] ?? sanitizedMetadata["traceId"]),
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
        textSanitizer.sanitize(text)
    }
}
