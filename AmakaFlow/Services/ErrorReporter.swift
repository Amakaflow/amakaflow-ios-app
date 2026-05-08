//
//  ErrorReporter.swift
//  AmakaFlow
//
//  AMA-1803 P0: thin wrapper that drops a user-initiated Sentry
//  breadcrumb when the user taps Report on an ErrorToast. Tags align
//  with AMA-1805's server-side capture (subsystem=endpoint_alerts,
//  failure_reason, request_id, error_code) so the user-side report
//  joins back to the matching server alert.
//
//  Wraps Sentry instead of calling sentry_sdk directly so test code
//  can inject a fake reporter without dragging the SDK into XCTest.
//

import Foundation
import Sentry

protocol ErrorReporting {
    func report(action: String, error: CTAError)
}

final class ErrorReporter: ErrorReporting {
    static let shared = ErrorReporter()

    func report(action: String, error: CTAError) {
        // Match the project's existing Sentry pattern (closure-based
        // scope mutation). Tag keys mirror AMA-1805's server-side
        // capture so a user "Report" tap joins the matching server
        // alert by request_id + failure_reason.
        SentrySDK.capture(
            message: "user_reported[\(action)]: \(error.sentryFailureCode)"
        ) { scope in
            scope.setTag(value: "endpoint_alerts", key: "subsystem")
            scope.setTag(value: action, key: "action")
            scope.setTag(value: error.sentryFailureCode, key: "failure_reason")
            if let requestId = error.requestId {
                scope.setTag(value: requestId, key: "request_id")
            }
            if case .lyingSuccess(_, let errorCode, _) = error, let code = errorCode {
                scope.setTag(value: code, key: "error_code")
            }
            if case .http(let status, _, _) = error {
                scope.setTag(value: "\(status)", key: "status_code")
            }
        }
    }
}
