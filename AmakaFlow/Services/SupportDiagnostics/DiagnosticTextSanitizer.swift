import Foundation

nonisolated struct DiagnosticTextSanitizer: Sendable {
    func sanitize(_ text: String) -> String {
        var sanitized = text
        sanitized = replace(
            pattern: #"(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+/\-=]+"#,
            in: sanitized,
            with: "$1\(DiagnosticRedactor.redacted)"
        )
        sanitized = replace(
            pattern: #"(?i)(bearer\s+)[A-Za-z0-9._~+/\-=]+"#,
            in: sanitized,
            with: "$1\(DiagnosticRedactor.redacted)"
        )
        sanitized = replace(
            pattern: #"\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,}\b"#,
            in: sanitized,
            with: DiagnosticRedactor.redacted
        )
        sanitized = replace(
            pattern: #"(?i)(cookie\s*:\s*)[^\n\r]+"#,
            in: sanitized,
            with: "$1\(DiagnosticRedactor.redacted)"
        )
        sanitized = replace(
            pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            in: sanitized,
            options: [.caseInsensitive],
            with: DiagnosticRedactor.redactedEmail
        )
        sanitized = redactURLQueries(in: sanitized)
        sanitized = replace(
            pattern: #"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{8,}\b|\bclerk_secret_[A-Za-z0-9_-]{4,}\b|\bAKIA[0-9A-Z]{16}\b"#,
            in: sanitized,
            options: [.caseInsensitive],
            with: DiagnosticRedactor.redacted
        )
        sanitized = replace(
            pattern: #"(?i)\b(access_token|refresh_token|id_token|api_key|client_secret|password)\b\s*[:=]\s*"?[^",\s}]+"?"#,
            in: sanitized
        ) { match in
            guard let separator = match.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                return DiagnosticRedactor.redacted
            }
            return "\(match[..<separator])\(match[separator]) \(DiagnosticRedactor.redacted)"
        }
        return sanitized
    }

    private func redactURLQueries(in text: String) -> String {
        let absoluteRedacted = replace(
            pattern: #"https?://[^\s?#]+(?:\?[^\s#]*)?(?:#[^\s]*)?"#,
            in: text
        ) { match in
            guard let url = URL(string: match),
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                return match.contains("?")
                    ? String(match.prefix { $0 != "?" }) + "?\(DiagnosticRedactor.redactedQuery)"
                    : match
            }
            if components.query != nil {
                components.query = DiagnosticRedactor.redactedQuery
            }
            return components.string
                ?? "\(url.scheme ?? "https")://\(url.host ?? "unknown")?\(DiagnosticRedactor.redactedQuery)"
        }
        return replace(
            pattern: #"(/[A-Za-z0-9._~%!$&'()*+,;=:@/-]+)\?[^\s#]+"#,
            in: absoluteRedacted
        ) { match in
            guard let queryStart = match.firstIndex(of: "?") else { return match }
            return "\(match[..<queryStart])?\(DiagnosticRedactor.redactedQuery)"
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
