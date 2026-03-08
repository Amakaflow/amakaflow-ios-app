//
//  SentryService.swift
//  AmakaFlow
//
//  Centralized error tracking and crash reporting using Sentry (AMA-225)
//

import Foundation
import Sentry

/// Centralized service for error tracking, crash reporting, and user feedback
@MainActor
final class SentryService {
    static let shared = SentryService()

    private init() {}

    // MARK: - User Context

    /// Set user context after successful pairing/authentication
    func setUser(userId: String, email: String? = nil) {
        SentrySDK.configureScope { scope in
            scope.setUser(Sentry.User(userId: userId))
        }
        print("[Sentry] User context set: \(userId)")
    }

    /// Clear user context on logout/unpair
    func clearUser() {
        SentrySDK.setUser(nil)
        print("[Sentry] User context cleared")
    }

    // MARK: - Error Capturing

    /// Capture an error with optional context
    func captureError(_ error: Error, context: [String: Any]? = nil) {
        SentrySDK.capture(error: error) { scope in
            if let context = context {
                for (key, value) in context {
                    scope.setExtra(value: value, key: key)
                }
            }
        }
    }

    /// Capture an API error with endpoint and status code
    func captureAPIError(_ error: Error, endpoint: String, statusCode: Int?, responseBody: String? = nil) {
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: endpoint, key: "api_endpoint")
            if let code = statusCode {
                scope.setTag(value: String(code), key: "status_code")
            }
            if let body = responseBody {
                scope.setExtra(value: String(body.prefix(1000)), key: "response_body")
            }
            scope.setTag(value: "api", key: "error_category")
        }
    }

    /// Capture a Watch communication error
    func captureWatchError(_ error: Error, context: String) {
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: "watch_communication", key: "error_category")
            scope.setExtra(value: context, key: "context")
        }
    }

    /// Capture a Garmin communication error
    func captureGarminError(_ error: Error, context: String) {
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: "garmin_communication", key: "error_category")
            scope.setExtra(value: context, key: "context")
        }
    }

    /// Capture a workout engine error
    func captureWorkoutError(_ error: Error, workoutId: String?, stepIndex: Int?) {
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: "workout", key: "error_category")
            if let id = workoutId {
                scope.setExtra(value: id, key: "workout_id")
            }
            if let step = stepIndex {
                scope.setExtra(value: step, key: "step_index")
            }
        }
    }

    // MARK: - Breadcrumbs

    /// Add a navigation breadcrumb
    func trackScreen(_ name: String) {
        let crumb = Breadcrumb(level: .info, category: "navigation")
        crumb.message = "Viewed \(name)"
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Add a workout action breadcrumb
    func trackWorkoutAction(_ action: String, workoutId: String? = nil, workoutName: String? = nil) {
        let crumb = Breadcrumb(level: .info, category: "workout")
        crumb.message = action
        var data: [String: Any] = [:]
        if let id = workoutId { data["workout_id"] = id }
        if let name = workoutName { data["workout_name"] = name }
        if !data.isEmpty { crumb.data = data }
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Add a pairing action breadcrumb
    func trackPairingAction(_ action: String) {
        let crumb = Breadcrumb(level: .info, category: "pairing")
        crumb.message = action
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Add a device connection breadcrumb
    func trackDeviceConnection(_ device: String, action: String) {
        let crumb = Breadcrumb(level: .info, category: "device")
        crumb.message = "\(device): \(action)"
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Performance Transactions (AMA-1083)

    /// Start a new performance transaction bound to no scope.
    /// The caller owns the returned span and must call `finish()` on it.
    nonisolated func startTransaction(name: String, operation: String) -> any Span {
        SentrySDK.startTransaction(name: name, operation: operation, bindToScope: false)
    }

    /// Finish a span with a given status (convenience wrapper).
    nonisolated func finish(_ span: any Span, status: SentrySpanStatus = .ok) {
        span.finish(status: status)
    }

    // MARK: - User Feedback

    /// Submit user feedback for a captured event
    func submitFeedback(comments: String, email: String? = nil, name: String? = nil) {
        let eventId = SentrySDK.capture(message: "User Feedback")
        let feedback = UserFeedback(eventId: eventId)
        feedback.comments = comments
        feedback.email = email ?? ""
        feedback.name = name ?? ""
        SentrySDK.capture(userFeedback: feedback)
        print("[Sentry] User feedback submitted")
    }

    /// Capture a message with attached debug logs
    func captureWithLogs(_ message: String, logs: String) {
        SentrySDK.capture(message: message) { scope in
            scope.setExtra(value: logs, key: "debug_logs")
        }
    }
}

// MARK: - Convenience Extensions

extension Error {
    /// Capture this error to Sentry with optional context
    func captureToSentry(context: [String: Any]? = nil) {
        Task { @MainActor in
            SentryService.shared.captureError(self, context: context)
        }
    }
}
