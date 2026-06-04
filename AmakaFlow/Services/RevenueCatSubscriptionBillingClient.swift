//
//  RevenueCatSubscriptionBillingClient.swift
//  AmakaFlow
//
//  RevenueCat SDK wrapper for iOS in-app subscriptions (AMA-1851).
//

import Foundation
import RevenueCat

@MainActor
final class RevenueCatSubscriptionBillingClient: SubscriptionBillingProviding {
    static let shared = RevenueCatSubscriptionBillingClient()

    /// Matches Clerk plan slug `pro` and RevenueCat entitlement identifier.
    static let proEntitlementIdentifier = "pro"

    private var configured = false

    var isConfigured: Bool { configured }

    private init() {}

    func configure(appUserID: String?) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        #endif

        guard let apiKey = AppEnvironment.current.revenueCatAPIKey, !apiKey.isEmpty else {
            return
        }

        if configured {
            Task { await syncAppUserID(appUserID) }
            return
        }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
        configured = true
    }

    func syncAppUserID(_ appUserID: String?) async {
        guard configured, let appUserID, !appUserID.isEmpty else { return }
        _ = try? await Purchases.shared.logIn(appUserID)
    }

    func customerHasProAccess() async throws -> Bool {
        guard configured else { return false }
        let info = try await Purchases.shared.customerInfo()
        return Self.hasActiveProEntitlement(info)
    }

    func loadPlanPricing() async throws -> SubscriptionPlanPricing? {
        guard configured else { return nil }
        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.current else { return nil }

        let monthly = offering.monthly ?? offering.availablePackages.first { $0.packageType == .monthly }
        let annual = offering.annual ?? offering.availablePackages.first { $0.packageType == .annual }

        return SubscriptionPlanPricing(
            monthlyPrice: monthly?.storeProduct.localizedPriceString,
            monthlySubtitle: monthly?.storeProduct.localizedDescription,
            annualPrice: annual?.storeProduct.localizedPriceString,
            annualSubtitle: annual?.storeProduct.localizedDescription,
            annualBadge: annual != nil ? "SAVE 42%" : nil
        )
    }

    func purchase(plan: SubscriptionBillingPlan) async throws -> Bool {
        guard configured else { throw SubscriptionBillingError.notConfigured }

        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.current else {
            throw SubscriptionBillingError.offeringUnavailable
        }

        let package: Package?
        switch plan {
        case .monthly:
            package = offering.monthly ?? offering.availablePackages.first { $0.packageType == .monthly }
        case .annual:
            package = offering.annual ?? offering.availablePackages.first { $0.packageType == .annual }
        }

        guard let package else {
            throw SubscriptionBillingError.packageUnavailable(plan)
        }

        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            throw SubscriptionBillingError.purchaseCancelled
        }
        return Self.hasActiveProEntitlement(result.customerInfo)
    }

    func restorePurchases() async throws -> Bool {
        guard configured else { throw SubscriptionBillingError.notConfigured }
        let info = try await Purchases.shared.restorePurchases()
        return Self.hasActiveProEntitlement(info)
    }

    private static func hasActiveProEntitlement(_ info: CustomerInfo) -> Bool {
        info.entitlements[proEntitlementIdentifier]?.isActive == true
    }
}
