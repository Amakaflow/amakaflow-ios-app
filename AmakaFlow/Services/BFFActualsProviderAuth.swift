//
//  BFFActualsProviderAuth.swift
//  AmakaFlow
//
//  AMA-2391: Live Strava OAuth via mobile-BFF + ASWebAuthenticationSession.
//  Garmin remains stubbed (out of scope for this ticket).
//

import AuthenticationServices
import Foundation
import UIKit

enum ActualsProviderAuthFactory {
    /// Live BFF Strava OAuth in app builds; stub for previews + UITEST fixtures.
    @MainActor
    static func makeDefault() -> any ActualsProviderAuthProviding {
        #if DEBUG
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isPreview || LaunchConfig.active?.useFixtures == true {
            return StubActualsProviderAuth()
        }
        #endif
        return BFFActualsProviderAuth.live()
    }
}

/// Presents Strava's authorize page and completes when strava-sync-api redirects
/// to `amakaflow://…/connected?status=success` (`FRONTEND_URL` on Render).
@MainActor
final class BFFActualsProviderAuth: NSObject, ActualsProviderAuthProviding {
    private let client: BFFStravaClient
    private var authSession: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<ActualsProviderAuthOutcome, Never>?

    init(client: BFFStravaClient) {
        self.client = client
        super.init()
    }

    static func live() -> BFFActualsProviderAuth {
        BFFActualsProviderAuth(client: .live())
    }

    func authorize(
        _ provider: ActualsSourceProvider,
        includeWrite: Bool
    ) async -> ActualsProviderAuthOutcome {
        switch provider {
        case .strava:
            return await authorizeStrava(includeWrite: includeWrite)
        case .garmin, .appleHealth:
            // Garmin OAuth is a separate ticket; never fake a link in Release.
            return .failed
        }
    }

    private func authorizeStrava(includeWrite: Bool) async -> ActualsProviderAuthOutcome {
        let authURL: URL
        do {
            authURL = try await client.initiateOAuth(includeWrite: includeWrite)
        } catch {
            return .failed
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<ActualsProviderAuthOutcome, Never>) in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: StravaOAuthCallback.urlScheme
            ) { [weak self] callbackURL, error in
                guard let self else { return }
                let outcome: ActualsProviderAuthOutcome
                if let error {
                    if let webError = error as? ASWebAuthenticationSessionError,
                       webError.code == .canceledLogin {
                        outcome = .cancelled
                    } else {
                        outcome = .failed
                    }
                } else if let callbackURL {
                    outcome = StravaOAuthCallback.outcome(from: callbackURL)
                } else {
                    outcome = .failed
                }
                self.finish(outcome)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                self.finish(.failed)
            }
        }
    }

    private func finish(_ outcome: ActualsProviderAuthOutcome) {
        authSession = nil
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

extension BFFActualsProviderAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return key
        }
        if let any = scenes.flatMap(\.windows).first {
            return any
        }
        return ASPresentationAnchor()
    }
}
