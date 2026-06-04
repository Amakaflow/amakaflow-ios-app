//
//  SubscriptionBilling.swift
//  AmakaFlow
//
//  Abstractions for RevenueCat / StoreKit subscription flows (AMA-1851).
//

import Foundation

enum SubscriptionBillingPlan: String, CaseIterable, Sendable {
    case monthly
    case annual
}

enum SubscriptionBillingError: LocalizedError, Equatable {
    case notConfigured
    case offeringUnavailable
    case packageUnavailable(SubscriptionBillingPlan)
    case purchaseCancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Subscriptions are not available in this build yet."
        case .offeringUnavailable:
            return "Subscription plans could not be loaded. Try again later."
        case .packageUnavailable(let plan):
            return "The \(plan.rawValue) plan is not available right now."
        case .purchaseCancelled:
            return nil
        }
    }
}

struct SubscriptionPlanPricing: Equatable {
    let monthlyPrice: String?
    let monthlySubtitle: String?
    let annualPrice: String?
    let annualSubtitle: String?
    let annualBadge: String?
}

@MainActor
protocol SubscriptionBillingProviding: AnyObject {
    var isConfigured: Bool { get }
    func configure(appUserID: String?)
    func syncAppUserID(_ appUserID: String?) async
    func customerHasProAccess() async throws -> Bool
    func loadPlanPricing() async throws -> SubscriptionPlanPricing?
    func purchase(plan: SubscriptionBillingPlan) async throws -> Bool
    func restorePurchases() async throws -> Bool
}

@MainActor
final class NoOpSubscriptionBillingClient: SubscriptionBillingProviding {
    var isConfigured: Bool { false }

    func configure(appUserID: String?) {}

    func syncAppUserID(_ appUserID: String?) async {}

    func customerHasProAccess() async throws -> Bool { false }

    func loadPlanPricing() async throws -> SubscriptionPlanPricing? { nil }

    func purchase(plan: SubscriptionBillingPlan) async throws -> Bool {
        throw SubscriptionBillingError.notConfigured
    }

    func restorePurchases() async throws -> Bool {
        throw SubscriptionBillingError.notConfigured
    }
}
