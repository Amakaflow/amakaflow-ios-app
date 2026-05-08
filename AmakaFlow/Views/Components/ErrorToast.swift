//
//  ErrorToast.swift
//  AmakaFlow
//
//  AMA-1803 P0: reusable toast that surfaces a CTAError with an
//  honest verdict, an optional Retry, and a Report button that
//  drops a Sentry breadcrumb correlated to AMA-1805's server tags.
//

import SwiftUI

struct ErrorToast: View {
    /// Short label naming the action that failed
    /// (e.g. "Couldn't save workout"). Always shown in bold.
    let actionTitle: String

    /// Typed error model — drives the body copy + Retry visibility.
    let error: CTAError

    /// Called when the user taps Retry. Nil = no Retry button.
    var onRetry: (() -> Void)? = nil

    /// Called when the user taps Report. Implementations should
    /// drop a Sentry breadcrumb with the CTAError's `requestId` and
    /// `sentryFailureCode` so support can join it back to the
    /// matching server-side AMA-1805 alert.
    var onReport: (() -> Void)? = nil

    /// Called when the user dismisses the toast (X tap or
    /// programmatic). Nil = non-dismissible (caller controls
    /// visibility via state).
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(error.userMessage)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(8)
                    }
                    .accessibilityLabel("Dismiss")
                }
            }

            // Action row: Retry (if applicable) + Report (always)
            HStack(spacing: 8) {
                if error.isRetryable, let onRetry = onRetry {
                    Button(action: onRetry) {
                        Text("Retry")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.18))
                            .clipShape(Capsule())
                            .foregroundColor(.white)
                    }
                    .accessibilityIdentifier("error_toast_retry")
                }

                if let onReport = onReport {
                    Button(action: onReport) {
                        Text("Report")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.12))
                            .clipShape(Capsule())
                            .foregroundColor(.white)
                    }
                    .accessibilityIdentifier("error_toast_report")
                }

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            // Distinct red so failure is unmistakable. NOT a
            // "warning yellow" — yellow trains users to ignore.
            LinearGradient(
                colors: [Color.red, Color.red.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("error_toast")
    }

    private var iconName: String {
        switch error {
        case .network: return "wifi.exclamationmark"
        case .http: return "server.rack"
        case .lyingSuccess: return "exclamationmark.triangle.fill"
        case .decoding: return "doc.text.magnifyingglass"
        case .unauthenticated: return "lock.fill"
        case .unknown: return "exclamationmark.circle.fill"
        }
    }
}

#Preview("HTTP 500 with Retry") {
    ErrorToast(
        actionTitle: "Couldn't save workout",
        error: .http(status: 500, body: "internal server error", requestId: "req-abc-123"),
        onRetry: {},
        onReport: {},
        onDismiss: {}
    )
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Lying success (AMA-1798 path)") {
    ErrorToast(
        actionTitle: "Couldn't save workout",
        error: .lyingSuccess(
            message: "Failed to save workout completion",
            errorCode: "UNKNOWN_ERROR",
            requestId: "req-xyz-789"
        ),
        onReport: {},
        onDismiss: {}
    )
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Network error (offline)") {
    ErrorToast(
        actionTitle: "Couldn't save workout",
        error: .network(code: .notConnectedToInternet),
        onRetry: {},
        onReport: {},
        onDismiss: {}
    )
    .padding()
    .background(Color(.systemBackground))
}
