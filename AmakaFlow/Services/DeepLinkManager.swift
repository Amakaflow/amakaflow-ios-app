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

    /// AMA-1811: convenience binding for `.alert(isPresented:)` modifiers.
    /// Reads as true when `unrecognizedLink` is non-nil; setting false
    /// clears the URL.
    var showUnrecognizedLinkAlert: Bool {
        get { unrecognizedLink != nil }
        set { if !newValue { unrecognizedLink = nil } }
    }

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
            pendingImportURL = workoutURL
            showImportSheet = true
            return true

        case .unknown:
            // AMA-1811: surface the unrecognized link to the user
            // instead of silently dropping it. Earlier behaviour was
            // a debug-only print — invisible in TestFlight builds AND
            // invisible to ops. The user just saw their tap do
            // nothing.
            #if DEBUG
            print("[DeepLinkManager] Unrecognized deep link: \(url.absoluteString)")
            #endif
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
                scope.setExtra(value: url.absoluteString, key: "url")
            }
            return false
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

        // Validate the extracted URL is a valid HTTP(S) URL
        guard urlParam.lowercased().hasPrefix("http://") || urlParam.lowercased().hasPrefix("https://") else {
            return .unknown
        }

        return .importURL(urlParam)
    }

    // MARK: - Helpers

    /// Check if the URL is a Universal Link from our domains
    private func isAmakaFlowUniversalLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "amakaflow.com" || host == "app.amakaflow.com"
    }
}
