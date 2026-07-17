//
//  CTAErrorTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1803 P0 unit coverage for the canonical CTA failure model.
//
//  Per the audit acceptance criteria, every primary CTA's view-model
//  must handle (success, success:false, 4xx, 5xx, network) explicitly.
//  CTAError.map() is the bottleneck — if it misclassifies any of those
//  five shapes, every CTA downstream is wrong. These tests lock the
//  classification.
//

import XCTest
@testable import AmakaFlowCompanion

final class CTAErrorTests: XCTestCase {

    // MARK: - Mapping from APIError

    func test_map_unauthorized_classifies_as_unauthenticated() {
        let cta = CTAError.map(APIError.unauthorized, requestId: "req-1")

        guard case .unauthenticated(let reqId) = cta else {
            return XCTFail("expected .unauthenticated, got \(cta)")
        }
        XCTAssertEqual(reqId, "req-1")
        XCTAssertEqual(cta.sentryFailureCode, "unauthenticated")
        XCTAssertFalse(cta.isRetryable, "unauthenticated must NOT show Retry — user has to sign in again")
    }

    func test_map_serverError_4xx_classifies_as_http_no_retry() {
        let cta = CTAError.map(APIError.serverError(404), requestId: "req-2")

        guard case .http(let status, let body, let reqId) = cta else {
            return XCTFail("expected .http, got \(cta)")
        }
        XCTAssertEqual(status, 404)
        XCTAssertNil(body)
        XCTAssertEqual(reqId, "req-2")
        XCTAssertEqual(cta.sentryFailureCode, "http_404")
        XCTAssertFalse(cta.isRetryable, "4xx must NOT offer Retry")
    }

    func test_map_serverError_5xx_classifies_as_http_with_retry() {
        let cta = CTAError.map(APIError.serverError(503), requestId: "req-3")

        guard case .http(let status, _, _) = cta else {
            return XCTFail("expected .http, got \(cta)")
        }
        XCTAssertEqual(status, 503)
        XCTAssertTrue(cta.isRetryable, "5xx is transient — must offer Retry")
    }

    func test_map_serverErrorWithBody_5xx_preserves_body() {
        let body = "internal server error"
        let cta = CTAError.map(APIError.serverErrorWithBody(500, body), requestId: nil)

        guard case .http(let status, let receivedBody, _) = cta else {
            return XCTFail("expected .http, got \(cta)")
        }
        XCTAssertEqual(status, 500)
        XCTAssertEqual(receivedBody, body)
        XCTAssertTrue(cta.isRetryable)
    }

    // MARK: - Lying success (the AMA-1798/1799/1800 path)

    func test_map_lying_success_200_extracts_message_and_errorCode() {
        // Exactly the body shape AMA-1798 produced before being fixed.
        let body = "{\"success\":false,\"message\":\"Failed to save workout completion\",\"error_code\":\"UNKNOWN_ERROR\"}"
        let cta = CTAError.map(APIError.serverErrorWithBody(200, body), requestId: "req-lying")

        guard case .lyingSuccess(let message, let errorCode, let reqId) = cta else {
            return XCTFail("expected .lyingSuccess (the AMA-1798 path), got \(cta)")
        }
        XCTAssertEqual(message, "Failed to save workout completion")
        XCTAssertEqual(errorCode, "UNKNOWN_ERROR")
        XCTAssertEqual(reqId, "req-lying")
        XCTAssertEqual(cta.sentryFailureCode, "lying_success_200")
        XCTAssertFalse(cta.isRetryable, "lying_success is deterministic — Retry would just re-fail")
    }

    func test_map_lying_success_with_spaces_in_json_still_extracts() {
        // Some servers emit the body with whitespace after the colon.
        let body = "{ \"success\": false, \"message\": \"Bad payload\", \"error_code\": \"VALIDATION\" }"
        let cta = CTAError.map(APIError.serverErrorWithBody(200, body), requestId: nil)

        guard case .lyingSuccess(let message, let errorCode, _) = cta else {
            return XCTFail("expected .lyingSuccess for `\"success\": false` (spaced), got \(cta)")
        }
        XCTAssertEqual(message, "Bad payload")
        XCTAssertEqual(errorCode, "VALIDATION")
    }

    func test_map_real_success_200_does_NOT_classify_as_lyingSuccess() {
        // Negative case: real 200 with success:true must not be reported.
        // (CTAError.map is normally only called from a catch block; this
        // guards the body-detection path against false positives if a
        // future caller routes a 200-success body through it.)
        let body = "{\"success\":true,\"id\":\"c-1\"}"
        let cta = CTAError.map(APIError.serverErrorWithBody(200, body))

        if case .lyingSuccess = cta {
            return XCTFail("real success body must NOT classify as lyingSuccess; got \(cta)")
        }
    }

    // MARK: - extractField edge cases (CR regression)

    func test_extractField_handles_escaped_quotes_inside_message() {
        // CR finding: the manual scan would happily return the wrong
        // value for a body where a string field contains an escaped
        // quote BEFORE the actual value. Verify JSONSerialization
        // first-pass picks the right value.
        let body = #"{"success":false,"message":"He said \"oops\" before everything failed","error_code":"BOOM"}"#
        let cta = CTAError.map(APIError.serverErrorWithBody(200, body))
        guard case .lyingSuccess(let message, let errorCode, _) = cta else {
            return XCTFail("expected .lyingSuccess, got \(cta)")
        }
        XCTAssertEqual(message, "He said \"oops\" before everything failed")
        XCTAssertEqual(errorCode, "BOOM")
    }

    func test_extractField_skips_key_substring_inside_value() {
        // CR finding: a body where the SAME key name appears inside
        // a different field's value would mis-extract under the manual
        // scan. JSONSerialization must pick the structural occurrence.
        let body = #"{"success":false,"message":"the error_code is invalid","error_code":"REAL_CODE"}"#
        let cta = CTAError.map(APIError.serverErrorWithBody(200, body))
        guard case .lyingSuccess(_, let errorCode, _) = cta else {
            return XCTFail("expected .lyingSuccess, got \(cta)")
        }
        XCTAssertEqual(errorCode, "REAL_CODE", "extractor must return the structural value, not the substring inside the message")
    }

    func test_extractField_handles_multiline_pretty_printed_body() {
        // CR finding: tab/newline JSON spacing should still classify
        // as lying-success and correctly extract message + error_code.
        let body = """
        {
        \t"success": false,
        \t"message": "validation failed",
        \t"error_code": "AMA_VAL"
        }
        """
        let cta = CTAError.map(APIError.serverErrorWithBody(200, body))
        guard case .lyingSuccess(let message, let errorCode, _) = cta else {
            return XCTFail("expected .lyingSuccess for multiline JSON, got \(cta)")
        }
        XCTAssertEqual(message, "validation failed")
        XCTAssertEqual(errorCode, "AMA_VAL")
    }

    func test_lying_success_classifies_for_201_too() {
        // CR finding: AMA-271 detection currently lives in the
        // 200/201 branch of APIService. Lock that 201 also triggers
        // the lying-success path so a future "create resource"
        // endpoint that returns 201 + success:false isn't silent.
        let body = "{\"success\":false,\"error_code\":\"DUP\"}"
        let cta = CTAError.map(APIError.serverErrorWithBody(201, body))
        guard case .lyingSuccess(_, let errorCode, _) = cta else {
            return XCTFail("expected .lyingSuccess for 201 + success:false, got \(cta)")
        }
        XCTAssertEqual(errorCode, "DUP")
    }

    func test_lying_success_does_NOT_classify_for_4xx_with_success_false() {
        // Negative case: a body containing `success:false` on a 4xx
        // should classify as plain HTTP, not lying-success — the
        // status code itself already tells the truth.
        let body = "{\"success\":false}"
        let cta = CTAError.map(APIError.serverErrorWithBody(400, body))
        guard case .http(let status, _, _) = cta else {
            return XCTFail("4xx must classify as .http even with success:false body, got \(cta)")
        }
        XCTAssertEqual(status, 400)
    }

    // MARK: - isRetryable narrowed for non-transient URLError codes (CR fix)

    // MARK: - PR #181 CR fixes

    func test_map_notFound_classifies_as_http_404_not_unknown() {
        // CR-fix on PR #181: APIError.notFound previously collapsed
        // into .unknown, which made the toast generic and the
        // isRetryable flag incorrect (.unknown returns false but
        // for the wrong reason — there's no status_code tag in
        // Sentry either). Surface as a real .http(404).
        let cta = CTAError.map(APIError.notFound, requestId: "req-nf")
        guard case .http(let status, _, let reqId) = cta else {
            return XCTFail(".notFound must classify as .http(404), got \(cta)")
        }
        XCTAssertEqual(status, 404)
        XCTAssertEqual(reqId, "req-nf")
        XCTAssertEqual(cta.sentryFailureCode, "http_404")
        XCTAssertFalse(cta.isRetryable, "404 is deterministic")
    }

    func test_isRetryable_false_for_handshake_and_redirect_errors() {
        // CR-fix on PR #181: earlier draft included
        // .serverCertificateUntrusted, .clientCertificateRequired,
        // .clientCertificateRejected, .httpTooManyRedirects and
        // .secureConnectionFailed in the transient list. Those are
        // deterministic configuration / handshake failures —
        // retrying just re-fails. Lock them as non-retryable.
        XCTAssertFalse(CTAError.network(code: .serverCertificateUntrusted).isRetryable)
        XCTAssertFalse(CTAError.network(code: .clientCertificateRequired).isRetryable)
        XCTAssertFalse(CTAError.network(code: .clientCertificateRejected).isRetryable)
        XCTAssertFalse(CTAError.network(code: .httpTooManyRedirects).isRetryable)
        XCTAssertFalse(CTAError.network(code: .secureConnectionFailed).isRetryable)
    }

    func test_isRetryable_false_for_non_transient_url_errors() {
        // CR finding: previous draft treated EVERY URLError as
        // retryable, including programmer errors like .badURL. Lock
        // that those don't show Retry.
        let badURL = CTAError.network(code: .badURL)
        XCTAssertFalse(badURL.isRetryable, ".badURL is a programmer error, not transient")

        let unsupported = CTAError.network(code: .unsupportedURL)
        XCTAssertFalse(unsupported.isRetryable, ".unsupportedURL is deterministic")

        let badServer = CTAError.network(code: .badServerResponse)
        XCTAssertFalse(badServer.isRetryable, ".badServerResponse should NOT show Retry")
    }

    func test_isRetryable_true_for_transient_url_errors() {
        XCTAssertTrue(CTAError.network(code: .timedOut).isRetryable)
        XCTAssertTrue(CTAError.network(code: .notConnectedToInternet).isRetryable)
        XCTAssertTrue(CTAError.network(code: .networkConnectionLost).isRetryable)
        XCTAssertTrue(CTAError.network(code: .cannotConnectToHost).isRetryable)
        XCTAssertTrue(CTAError.network(code: .dnsLookupFailed).isRetryable)
    }

    // MARK: - AnnotatedAPIError unwrapping (AMA-1808 regression)

    func test_map_AnnotatedAPIError_propagates_requestId_into_CTAError() {
        // CR-fix (AMA-1808): the AnnotatedAPIError wrapper carries the
        // X-Request-ID extracted from the failing HTTPURLResponse.
        // CTAError.map MUST surface that into the resulting variant
        // so the user-facing Report breadcrumb joins back to AMA-1805
        // server alerts by request_id.
        let annotated = AnnotatedAPIError(
            .serverErrorWithBody(
                200,
                "{\"success\":false,\"error_code\":\"WIRED\"}"
            ),
            requestId: "req-from-response-header"
        )
        let cta = CTAError.map(annotated)

        XCTAssertEqual(cta.requestId, "req-from-response-header",
                       "AnnotatedAPIError.requestId must propagate through CTAError.map")
        if case .lyingSuccess(_, let errorCode, let reqId) = cta {
            XCTAssertEqual(errorCode, "WIRED")
            XCTAssertEqual(reqId, "req-from-response-header")
        } else {
            XCTFail("expected .lyingSuccess after unwrapping annotated wrapper, got \(cta)")
        }
    }

    func test_map_AnnotatedAPIError_with_nil_requestId_falls_back_to_caller_hint() {
        // If the wrapper happened to be missing the header (server
        // didn't set X-Request-ID), the caller-supplied hint takes
        // over so we never silently drop correlation when one side
        // can supply a value.
        let annotated = AnnotatedAPIError(.unauthorized, requestId: nil)
        let cta = CTAError.map(annotated, requestId: "fallback-id")

        XCTAssertEqual(cta.requestId, "fallback-id")
        if case .unauthenticated = cta {
            // ok
        } else {
            XCTFail("expected .unauthenticated, got \(cta)")
        }
    }

    func test_map_AnnotatedAPIError_with_both_set_prefers_wrapper() {
        // When both the wrapper AND the caller hint are populated,
        // the wrapper wins (it's closer to the actual response).
        let annotated = AnnotatedAPIError(.serverError(503), requestId: "from-header")
        let cta = CTAError.map(annotated, requestId: "from-caller")

        XCTAssertEqual(cta.requestId, "from-header",
                       "wrapper requestId takes precedence over caller hint")
    }

    // MARK: - userMessage edge cases (CR fix for lyingSuccess copy)

    func test_userMessage_lying_success_with_only_errorCode_keeps_it() {
        // CR finding: previous draft dropped errorCode when message was nil.
        let cta = CTAError.lyingSuccess(message: nil, errorCode: "DB_TIMEOUT", requestId: nil)
        XCTAssertTrue(cta.userMessage.contains("DB_TIMEOUT"),
                      "userMessage must surface error_code even when message is absent; got: \(cta.userMessage)")
    }

    func test_userMessage_lying_success_with_only_message_uses_it() {
        let cta = CTAError.lyingSuccess(message: "Failed", errorCode: nil, requestId: nil)
        XCTAssertEqual(cta.userMessage, "Failed")
    }

    func test_userMessage_lying_success_with_neither_falls_back() {
        let cta = CTAError.lyingSuccess(message: nil, errorCode: nil, requestId: nil)
        XCTAssertEqual(cta.userMessage, "Server reported failure.")
    }

    // MARK: - Network errors

    func test_map_networkError_offline_classifies_as_network() {
        let urlErr = URLError(.notConnectedToInternet)
        let cta = CTAError.map(APIError.networkError(urlErr), requestId: nil)

        guard case .network(let code, _) = cta else {
            return XCTFail("expected .network, got \(cta)")
        }
        XCTAssertEqual(code, .notConnectedToInternet)
        XCTAssertTrue(cta.isRetryable, "offline is the canonical retryable case")
        XCTAssertEqual(cta.sentryFailureCode, "network")
    }

    func test_map_raw_URLError_classifies_as_network() {
        // CTAError.map should also handle a bare URLError without it
        // being wrapped in APIError — happens when the raw URLSession
        // call escapes before APIService translates it.
        let cta = CTAError.map(URLError(.timedOut))

        guard case .network(let code, _) = cta else {
            return XCTFail("expected .network for raw URLError, got \(cta)")
        }
        XCTAssertEqual(code, .timedOut)
    }

    func test_isCancellation_detects_URLError_cancelled_and_CancellationError() {
        XCTAssertTrue(CTAError.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(CTAError.isCancellation(CancellationError()))
        XCTAssertTrue(CTAError.isCancellation(APIError.networkError(URLError(.cancelled))))
        XCTAssertTrue(CTAError.isCancellation(APIError.network(underlying: CancellationError())))
        XCTAssertFalse(CTAError.isCancellation(URLError(.timedOut)))
    }

    func test_map_cancelled_does_not_classify_as_network_minus_999() {
        let cta = CTAError.map(URLError(.cancelled))
        guard case .unknown(let description, _) = cta else {
            return XCTFail("expected .unknown for cancelled, got \(cta)")
        }
        XCTAssertTrue(description.lowercased().contains("cancel"))
        if case .network(let code, _) = cta {
            XCTFail("cancelled must not map to .network(\(code.rawValue))")
        }
    }

    // MARK: - Decoding

    func test_map_decoding_error_classifies_as_decoding() {
        struct Dummy: Codable { let x: Int }
        let badJSON = Data("{}".utf8)
        var underlying: Error!
        do {
            _ = try JSONDecoder().decode(Dummy.self, from: badJSON)
        } catch {
            underlying = error
        }
        let cta = CTAError.map(APIError.decodingError(underlying), requestId: "req-dec")

        guard case .decoding(_, let reqId) = cta else {
            return XCTFail("expected .decoding, got \(cta)")
        }
        XCTAssertEqual(reqId, "req-dec")
        XCTAssertFalse(cta.isRetryable, "decoding error is deterministic — bug, not transient")
        XCTAssertEqual(cta.sentryFailureCode, "decoding")
    }

    // MARK: - Unknown / fallback

    func test_map_unknown_error_falls_back_to_unknown_variant() {
        struct CustomError: Error {
            let message: String
            var localizedDescription: String { message }
        }
        let cta = CTAError.map(CustomError(message: "weird"))

        guard case .unknown = cta else {
            return XCTFail("unmapped errors must classify as .unknown, got \(cta)")
        }
    }

    // MARK: - User-facing copy

    func test_userMessage_lying_success_includes_error_code() {
        let cta = CTAError.lyingSuccess(
            message: "Failed to save",
            errorCode: "UNKNOWN_ERROR",
            requestId: nil
        )
        XCTAssertEqual(cta.userMessage, "Failed to save (UNKNOWN_ERROR)")
    }

    func test_userMessage_offline_is_friendly_not_raw_code() {
        let cta = CTAError.network(code: .notConnectedToInternet)
        XCTAssertEqual(cta.userMessage, "No internet connection.")
    }

    func test_userMessage_500_includes_status_and_truncated_body() {
        let cta = CTAError.http(status: 500, body: "boom", requestId: nil)
        XCTAssertTrue(cta.userMessage.contains("500"))
        XCTAssertTrue(cta.userMessage.contains("boom"))
    }
}
