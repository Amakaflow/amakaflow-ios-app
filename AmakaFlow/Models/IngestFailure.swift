//
//  IngestFailure.swift
//  AmakaFlow
//
//  AMA-2470 (epic AMA-2463) — client half of the typed ingest failure contract.
//  The ingestor now returns `{"detail": <legacy prose>, "failure": {...}}` so the
//  app can branch on a code instead of sniffing substrings out of prose.
//  Legacy `detail` keeps arriving, so the old sniffers stay as a fallback for
//  servers/endpoints that never emit `failure`.
//

import Foundation

/// Typed ingest failure codes — mirrors `failure_codes.IngestFailureCode` in
/// `workout-ingestor-api`. Unknown wire values decode to `.unknown` rather than
/// failing the decode: an unrecognised code must never become "no internet".
enum IngestFailureCode: String, Equatable {
    case invalidURL = "invalid_url"
    case unsupportedPlatform = "unsupported_platform"
    case apifyStartFailed = "apify_start_failed"
    case apifyRunFailed = "apify_run_failed"
    case apifyTimeout = "apify_timeout"
    case apifyEmptyResult = "apify_empty_result"
    case contentUnavailable = "content_unavailable"
    case contentPrivateOrLoginRequired = "content_private_or_login_required"
    case normalizationFailed = "normalization_failed"
    case llmTimeout = "llm_timeout"
    case llmRefusalOrUnusableOutput = "llm_refusal_or_unusable_output"
    case schemaInvalid = "schema_invalid"
    case zeroExercisesExtracted = "zero_exercises_extracted"
    case mobileContractMismatch = "mobile_contract_mismatch"
    case unknown

    init(wireValue: String) {
        self = IngestFailureCode(rawValue: wireValue) ?? .unknown
    }
}

/// Pipeline stage the failure happened in — mirrors `failure_codes.IngestStage`.
enum IngestStage: String, Equatable {
    case submit
    case canonicalize
    case fetch
    case normalize
    case classify
    case extract
    case validate
    case deliveryContract = "delivery_contract"
    case unknown

    init(wireValue: String) {
        self = IngestStage(rawValue: wireValue) ?? .unknown
    }
}

/// Decoded `failure` envelope. `retryable` comes from the server — the client
/// never re-derives it, so a server policy change lands without an app release.
struct IngestFailure: Equatable {
    let code: IngestFailureCode
    let stage: IngestStage
    let retryable: Bool
    /// Server copy for the athlete. Preferred over any local string when non-empty.
    let serverUserMessage: String?
    /// `ingestion_attempts` row id (AMA-2465) when the server sent one.
    let attemptID: String?

    init(
        code: IngestFailureCode,
        stage: IngestStage,
        retryable: Bool,
        serverUserMessage: String? = nil,
        attemptID: String? = nil
    ) {
        self.code = code
        self.stage = stage
        self.retryable = retryable
        self.serverUserMessage = serverUserMessage
        self.attemptID = attemptID
    }

    /// Short banner title — distinct per family so "why" is answerable at a glance.
    var title: String {
        switch code {
        case .invalidURL:
            return "Link doesn't look right"
        case .unsupportedPlatform:
            return "Site not supported yet"
        case .contentUnavailable:
            return "Post unavailable"
        case .contentPrivateOrLoginRequired:
            return "Post is private"
        case .apifyStartFailed, .apifyRunFailed, .apifyTimeout, .apifyEmptyResult:
            return "Couldn't fetch the post"
        case .normalizationFailed, .llmTimeout, .llmRefusalOrUnusableOutput:
            return "Couldn't read the workout"
        case .schemaInvalid:
            return "Couldn't build the workout"
        case .zeroExercisesExtracted:
            return "Not enough exercises"
        case .mobileContractMismatch:
            return "Something went wrong on our side"
        case .unknown:
            return "Import failed"
        }
    }

    /// Copy shown to the athlete. Server `user_message` wins; the local table is
    /// the fallback for a code whose message the server omitted.
    var userMessage: String {
        if let serverUserMessage,
           !serverUserMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return serverUserMessage
        }
        return Self.localUserMessage(for: code)
    }

    /// Local mirror of the server's `_USER_MESSAGES` table — used only when the
    /// server omitted `user_message`. A table, not a switch: adding a code should
    /// never be a control-flow change.
    private static let localUserMessages: [IngestFailureCode: String] = [
        .invalidURL: "That link doesn't look right — check it and try again.",
        .unsupportedPlatform: "We can't import from this site yet. Paste the workout text instead.",
        .contentUnavailable: "This post isn't available — it may have been removed.",
        .contentPrivateOrLoginRequired: "This post is private, so we can't read it.",
        .apifyStartFailed: "We couldn't start fetching this post. Try again in a moment.",
        .apifyRunFailed: "We couldn't retrieve this post. Try again in a moment.",
        .apifyTimeout: "Fetching this post took too long. Try again in a moment.",
        .apifyEmptyResult: "We couldn't retrieve usable content from this post yet.",
        .normalizationFailed: "We fetched this post but couldn't read its content.",
        .llmTimeout: "Reading the workout took too long. Try again in a moment.",
        .llmRefusalOrUnusableOutput: "Our workout reader hit a problem. Try again in a moment.",
        .schemaInvalid: "We read this post but couldn't build a valid workout from it.",
        .zeroExercisesExtracted: "We couldn't find enough exercises in this post. "
            + "Try a screenshot, or create the workout manually.",
        .mobileContractMismatch:
            "Something went wrong showing this workout. We're on it — nothing is wrong with the post.",
        .unknown: "Import failed. Try again in a moment."
    ]

    private static func localUserMessage(for code: IngestFailureCode) -> String {
        localUserMessages[code] ?? localUserMessages[.unknown] ?? "Import failed. Try again in a moment."
    }

    // MARK: - Wire decoding

    /// Decode the typed envelope out of an HTTP error body.
    /// Returns nil when the body has no `failure` object (older server, other endpoint).
    static func decode(fromBody body: String?) -> IngestFailure? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return decode(fromEnvelope: object)
    }

    /// Decode from an already-parsed envelope (`{detail, failure}` or a task-status body).
    static func decode(fromEnvelope object: [String: Any]) -> IngestFailure? {
        guard let raw = object["failure"] as? [String: Any] else { return nil }
        guard let codeValue = raw["code"] as? String else { return nil }

        let code = IngestFailureCode(wireValue: codeValue)
        let stage = IngestStage(wireValue: (raw["stage"] as? String) ?? "")
        let debug = raw["debug"] as? [String: Any]
        let attemptID = (debug?["attempt_id"] as? String)
            ?? (debug?["attemptId"] as? String)
            ?? (object["attempt_id"] as? String)
            ?? (object["attemptId"] as? String)

        return IngestFailure(
            code: code,
            stage: stage,
            // Absent `retryable` is treated as not retryable: offering a retry that
            // can never succeed is a worse lie than withholding one.
            retryable: (raw["retryable"] as? Bool) ?? false,
            serverUserMessage: raw["user_message"] as? String,
            attemptID: attemptID?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
