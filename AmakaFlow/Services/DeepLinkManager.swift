//
//  DeepLinkManager.swift
//  AmakaFlow
//
//  Handles Universal Link and custom URL scheme deep links for workout import.
//  AMA-1259: Deep link import on iOS — Universal Links + custom scheme fallback
//

import Foundation
import Combine

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

    private init() {}

    // MARK: - Public API

    /// Handle an incoming URL from `.onOpenURL` or `UIApplicationDelegate`.
    /// Returns true if the URL was recognized and handled.
    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        let action = parseURL(url)

        switch action {
        case .importURL(let workoutURL):
            print("[DeepLinkManager] Import URL received: \(workoutURL)")
            pendingImportURL = workoutURL
            showImportSheet = true
            return true

        case .unknown:
            print("[DeepLinkManager] Unrecognized deep link: \(url.absoluteString)")
            return false
        }
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
