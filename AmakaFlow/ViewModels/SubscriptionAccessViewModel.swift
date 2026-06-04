//
//  SubscriptionAccessViewModel.swift
//  AmakaFlow
//
//  Resolves whether the signed-in user has Pro access via RevenueCat
//  entitlements and, when available, the backend subscription API.
//

import Combine
import Foundation

@MainActor
final class SubscriptionAccessViewModel: ObservableObject {
    @Published private(set) var hasProAccess: Bool
    @Published private(set) var isAccessResolved: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var planPricing: SubscriptionPlanPricing?
    @Published private(set) var subscription: Subscription?

    private let apiService: APIServiceProviding
    private let billingClient: SubscriptionBillingProviding
    private let userIdProvider: (() -> String?)?

    init(
        apiService: APIServiceProviding = AppDependencies.live.apiService,
        billingClient: SubscriptionBillingProviding? = nil,
        userIdProvider: (() -> String?)? = nil
    ) {
        self.apiService = apiService
        self.billingClient = billingClient ?? NoOpSubscriptionBillingClient()
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
        isLoading = true
        defer {
            isLoading = false
            isAccessResolved = true
        }

        let userId = resolvedUserId()
        billingClient.configure(appUserID: userId)
        await billingClient.syncAppUserID(userId)

        if billingClient.isConfigured {
            do {
                planPricing = try await billingClient.loadPlanPricing()
            } catch {
                planPricing = nil
            }
        }

        if try await resolveProAccessFromBilling() {
            return
        }

        do {
            let sub = try await apiService.fetchSubscription()
            subscription = sub
            hasProAccess = Self.isProSubscription(sub)
        } catch {
            subscription = nil
            hasProAccess = !FeatureFlags.paywallGateEnabled
        }
    }

    func purchase(plan: SubscriptionBillingPlan) async {
        purchaseError = nil
        isPurchasing = true
        defer { isPurchasing = false }

        billingClient.configure(appUserID: resolvedUserId())
        await billingClient.syncAppUserID(resolvedUserId())

        do {
            let granted = try await billingClient.purchase(plan: plan)
            hasProAccess = granted
            isAccessResolved = true
            if !granted {
                purchaseError = "Purchase did not activate AmakaFlow Pro."
            }
        } catch let error as SubscriptionBillingError where error == .purchaseCancelled {
            purchaseError = nil
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        isPurchasing = true
        defer { isPurchasing = false }

        billingClient.configure(appUserID: resolvedUserId())
        await billingClient.syncAppUserID(resolvedUserId())

        do {
            let restored = try await billingClient.restorePurchases()
            hasProAccess = restored
            isAccessResolved = true
            if !restored {
                purchaseError = "No active AmakaFlow Pro subscription was found for this Apple ID."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func resolveProAccessFromBilling() async -> Bool {
        guard billingClient.isConfigured else { return false }
        do {
            if try await billingClient.customerHasProAccess() {
                hasProAccess = true
                return true
            }
        } catch {
            // Fall through to backend subscription lookup.
        }
        return false
    }

    private func resolvedUserId() -> String? {
        userIdProvider?() ?? PairingService.shared.userProfile?.id
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
