//
//  StravaOAuthCallback.swift
//  AmakaFlow
//
//  AMA-2391: Parse the post-OAuth deep link from strava-sync-api.
//  Staging FRONTEND_URL must redirect to amakaflow://…/connected?status=…
//

import Foundation

enum StravaOAuthCallback {
    /// Registered in Info.plist (`CFBundleURLSchemes`).
    static let urlScheme = "amakaflow"

    /// Path segment the backend appends: `{FRONTEND_URL}/connected?…`.
    static let connectedPathMarker = "connected"

    /// Maps a completed ASWebAuthenticationSession callback URL to an auth outcome.
    static func outcome(from url: URL) -> ActualsProviderAuthOutcome {
        guard url.scheme?.lowercased() == urlScheme else { return .failed }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = (url.host.map { "/\($0)" } ?? "") + url.path
        let mentionsConnected = path.lowercased().contains(connectedPathMarker)
            || (url.host?.lowercased() == connectedPathMarker)

        guard mentionsConnected else { return .failed }

        let status = components?.queryItems?
            .first(where: { $0.name.lowercased() == "status" })?
            .value?
            .lowercased()

        switch status {
        case "success":
            return .success
        case "error":
            return .failed
        default:
            return .failed
        }
    }
}
