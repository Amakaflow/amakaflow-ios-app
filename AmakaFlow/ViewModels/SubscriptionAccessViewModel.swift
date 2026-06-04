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
    @Published private(set) var hasProAccess = true
    @Published private(set) var isLoading = false
    @Published private(set) var subscription: Subscription?

    private let apiService: APIServiceProviding

    init(apiService: APIServiceProviding = AppDependencies.live.apiService) {
        self.apiService = apiService
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

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
        UserDefaults.standard.set(true, forKey: Self.trialStartedKey)
        hasProAccess = true
    }

    var hasStartedTrial: Bool {
        UserDefaults.standard.bool(forKey: Self.trialStartedKey)
    }

    private static let trialStartedKey = "amakaflow_paywall_trial_started"

    private static func isProSubscription(_ sub: Subscription) -> Bool {
        switch sub.status {
        case .active, .trialing:
            return sub.plan.lowercased().contains("pro") || sub.plan != "free"
        case .pastDue, .canceled, .inactive:
            return false
        }
    }
}
