//
//  DeepLinkManager.swift
//  AmakaFlow
//
//  Handles Universal Link and custom URL scheme deep links for workout import.
//  AMA-1259: Deep link import on iOS — Universal Links + custom scheme fallback
//

import Foundation
import Combine
import Sentry

/// Parsed deep link action
enum DeepLinkAction: Equatable {
    /// Import a workout from a URL (e.g., YouTube, Instagram, TikTok)
    case importURL(String)

    /// Unknown or unhandled deep link
    case unknown
}

/// Manages parsing and routing of incoming deep links (Universal Links + custom scheme)
@MainActor
final class DeepLinkManager: ObservableObject {

    static let shared = DeepLinkManager()

    /// The currently pending import URL, observed by the UI to show the import sheet
    @Published var pendingImportURL: String?

    /// Whether the import sheet should be presented
    @Published var showImportSheet: Bool = false

    /// AMA-1811: holds the URL the user tried to open when no route
    /// matched, so the root view can render a "Couldn't open that
    /// link" alert. Earlier behaviour was a silent debug-only print
    /// that the user never saw — meaning a typo in a Universal Link
    /// or a stale deep-link target failed silently.
    @Published var unrecognizedLink: URL?

    private init() {}

    // MARK: - Public API

    /// Handle an incoming URL from `.onOpenURL` or `UIApplicationDelegate`.
    /// Returns true if the URL was recognized and handled.
    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        let action = parseURL(url)

        switch action {
        case .importURL(let workoutURL):
            #if DEBUG
            print("[DeepLinkManager] Import URL received: \(workoutURL)")
            #endif
            // A successful import supersedes any stale alert from a
            // prior unknown URL the user may have tapped.
            unrecognizedLink = nil
            pendingImportURL = workoutURL
            showImportSheet = true
            return true

        case .unknown:
            // AMA-1809 (CR): do NOT alert/report here. Other handlers
            // (Garmin Connect IQ, app-surface deep links) get a turn
            // first; only after they all fail does the caller invoke
            // `reportUnrecognizedLink(_:)`.
            #if DEBUG
            print("[DeepLinkManager] Unrecognized by importer: \(url.absoluteString)")
            #endif
            return false
        }
    }

    /// AMA-1811: surface an unrecognized deep link to the user once every
    /// other handler has declined it. Drops a redacted Sentry breadcrumb
    /// and flips `unrecognizedLink` so the root view can render an alert.
    /// AMA-1809 (CR): redacts query values from telemetry — deep-link URLs
    /// can carry tokens, emails, etc.
    func reportUnrecognizedLink(_ url: URL) {
        unrecognizedLink = url
        SentrySDK.capture(message: "deep_link.unrecognized") { scope in
            scope.setTag(value: "deep_link", key: "subsystem")
            scope.setTag(value: url.path, key: "path")
            if let host = url.host {
                scope.setTag(value: host, key: "host")
            }
            if let scheme = url.scheme {
                scope.setTag(value: scheme, key: "scheme")
            }
            scope.setLevel(SentryLevel.warning)
            let safeURL = "\(url.scheme ?? "")://\(url.host ?? "")\(url.path)"
            scope.setExtra(value: safeURL, key: "url")
            let queryKeys = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.map(\.name) ?? []
            if !queryKeys.isEmpty {
                scope.setExtra(value: queryKeys, key: "query_keys")
            }
        }
    }

    /// AMA-1811: dismiss the unrecognized-link alert. Called from the
    /// root view's `.alert(...).button(...)` action.
    func clearUnrecognizedLink() {
        unrecognizedLink = nil
    }

    /// Dismiss the import sheet and clear pending state
    func clearPendingImport() {
        pendingImportURL = nil
        showImportSheet = false
    }

    // MARK: - URL Parsing

    /// Parse an incoming URL into a DeepLinkAction.
    /// Supports both Universal Links and custom URL scheme.
    ///
    /// Universal Link examples:
    ///   https://amakaflow.com/import?url=https%3A%2F%2Fyoutu.be%2Fabc123
    ///   https://app.amakaflow.com/import?url=https%3A%2F%2Fyoutu.be%2Fabc123
    ///
    /// Custom scheme examples:
    ///   amakaflow://import?url=https%3A%2F%2Fyoutu.be%2Fabc123
    ///
    func parseURL(_ url: URL) -> DeepLinkAction {
        // Universal Links: https://amakaflow.com/import?url=...
        // Custom scheme:   amakaflow://import?url=...

        let isUniversalLink = isAmakaFlowUniversalLink(url)
        let isCustomScheme = url.scheme == "amakaflow"

        guard isUniversalLink || isCustomScheme else {
            return .unknown
        }

        // Check for /import path
        let path = url.path
        guard path == "/import" || (isCustomScheme && url.host == "import") else {
            return .unknown
        }

        // Extract the `url` query parameter
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
              !urlParam.isEmpty else {
            return .unknown
        }

        // Validate the extracted URL: https-only and known platform domain.
        // Rejects http:// (plaintext), non-allowlisted hosts (SSRF surface).
        guard isAllowedImportURL(urlParam) else {
            return .unknown
        }

        return .importURL(urlParam)
    }

    // MARK: - Helpers

    /// Known platform domains accepted as import URLs.
    /// Must be kept in sync with DeepLinkImportViewModel.detectPlatform.
    static let allowedImportDomains: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
        "instagram.com", "www.instagram.com", "m.instagram.com", "instagr.am",
        "tiktok.com", "www.tiktok.com", "m.tiktok.com",
        "pinterest.com", "www.pinterest.com", "pin.it",
        "twitter.com", "www.twitter.com", "mobile.twitter.com", "x.com", "www.x.com", "t.co",
        "facebook.com", "www.facebook.com", "m.facebook.com", "fb.watch", "fb.com",
        "reddit.com", "www.reddit.com", "redd.it",
    ]

    /// Returns true only for https:// URLs whose host is in the allowlist.
    private func isAllowedImportURL(_ urlString: String) -> Bool {
        guard let parsed = URL(string: urlString),
              parsed.scheme?.lowercased() == "https",
              let host = parsed.host?.lowercased() else {
            return false
        }
        return Self.allowedImportDomains.contains(host)
    }

    /// Check if the URL is a Universal Link from our domains
    private func isAmakaFlowUniversalLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "amakaflow.com" || host == "app.amakaflow.com"
    }
}
