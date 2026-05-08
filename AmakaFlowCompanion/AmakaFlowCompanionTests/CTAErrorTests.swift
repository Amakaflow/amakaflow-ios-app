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
