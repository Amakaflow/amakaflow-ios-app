//
//  StravaOAuthCallback.swift
//  AmakaFlow
//
//  AMA-2391: Parse the post-OAuth deep link from strava-sync-api.
//  Staging FRONTEND_URL must redirect to amakaflow://…/connected?status=…
//  AMA-2396: also reads `scope=` so write-back unlocks only on activity:write.
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

        let items = components?.queryItems ?? []
        let status = items
            .first { $0.name.lowercased() == "status" }?
            .value?
            .lowercased()

        switch status {
        case "success":
            let scope = items
                .first { $0.name.lowercased() == "scope" }?
                .value ?? ""
            return .success(grantedWrite: scopeContainsWrite(scope))
        case "error":
            return .failed
        default:
            return .failed
        }
    }

    /// Strava may return comma- or space-separated scopes
    /// (`activity:read_all,activity:write` or `activity:read_all activity:write`).
    static func scopeContainsWrite(_ scope: String) -> Bool {
        let normalized = scope
            .replacingOccurrences(of: ",", with: " ")
            .lowercased()
        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .contains("activity:write")
    }
}
