//
//  SubscriptionAccessViewModel.swift
//  AmakaFlow
//
//  Resolves whether the signed-in user has Pro access. Billing is not live
//  yet (`fetchSubscription` → notImplemented), so failures default to allowing
//  access unless the paywall preview gate is enabled for QA.
//

import Combine
import Foundation

@MainActor
final class SubscriptionAccessViewModel: ObservableObject {
    @Published private(set) var hasProAccess: Bool
    @Published private(set) var isAccessResolved: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var subscription: Subscription?

    private let apiService: APIServiceProviding
    private let userIdProvider: (() -> String?)?

    init(
        apiService: APIServiceProviding = AppDependencies.live.apiService,
        userIdProvider: (() -> String?)? = nil
    ) {
        self.apiService = apiService
        self.userIdProvider = userIdProvider
        if FeatureFlags.paywallGateEnabled {
            hasProAccess = false
            isAccessResolved = false
        } else {
            hasProAccess = true
            isAccessResolved = true
        }
    }

    func refresh() async {
        let userId = resolvedUserId()
        if hasStartedTrial(for: userId) {
            hasProAccess = true
            isAccessResolved = true
            return
        }

        isLoading = true
        defer {
            isLoading = false
            isAccessResolved = true
        }

        do {
            let sub = try await apiService.fetchSubscription()
            subscription = sub
            hasProAccess = Self.isProSubscription(sub)
        } catch {
            subscription = nil
            // Billing route is stubbed — keep MVP users unblocked unless QA gate is on.
            hasProAccess = !FeatureFlags.paywallGateEnabled
        }
    }

    /// Marks the user as having started a trial from the paywall shell (StoreKit TBD).
    func markTrialStarted() {
        let userId = resolvedUserId()
        UserDefaults.standard.set(true, forKey: Self.trialStartedKey(for: userId))
        hasProAccess = true
        isAccessResolved = true
    }

    func hasStartedTrial(for userId: String? = nil) -> Bool {
        UserDefaults.standard.bool(forKey: Self.trialStartedKey(for: userId ?? resolvedUserId()))
    }

    private func resolvedUserId() -> String? {
        userIdProvider?() ?? PairingService.shared.userProfile?.id
    }

    private static func trialStartedKey(for userId: String?) -> String {
        "amakaflow_paywall_trial_started_\(userId ?? "anonymous")"
    }

    static func isProSubscription(_ sub: Subscription) -> Bool {
        switch sub.status {
        case .active, .trialing:
            return sub.plan.lowercased().contains("pro")
        case .pastDue, .canceled, .inactive:
            return false
        }
    }
}
