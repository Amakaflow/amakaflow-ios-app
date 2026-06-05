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

        guard !configured else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
        configured = true
    }

    func syncAppUserID(_ appUserID: String?) async throws {
        guard configured else { return }
        guard let appUserID, !appUserID.isEmpty else { return }

        do {
            _ = try await Purchases.shared.logIn(appUserID)
        } catch {
            throw SubscriptionBillingError.identitySyncFailed
        }
    }

    func clearAppUserIdentity() async throws {
        guard configured else { return }

        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            throw SubscriptionBillingError.identitySyncFailed
        }
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
            monthlySubtitle: monthly.map { "\($0.storeProduct.localizedPriceString)/mo · 7-day trial" },
            annualPrice: annual?.storeProduct.localizedPriceString,
            annualSubtitle: Self.annualDisplaySubtitle(annual: annual),
            annualBadge: Self.annualSavingsBadge(monthly: monthly, annual: annual)
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

    static func annualDisplaySubtitle(annual: Package?) -> String? {
        guard let annual else { return nil }
        let yearly = annual.storeProduct.localizedPriceString
        guard let monthlyEquivalent = formattedMonthlyEquivalent(for: annual) else {
            return "\(yearly)/yr"
        }
        return "\(yearly)/yr · \(monthlyEquivalent)/mo"
    }

    static func formattedMonthlyEquivalent(for annual: Package) -> String? {
        let monthlyPrice = annual.storeProduct.price / 12
        guard monthlyPrice > 0 else { return nil }
        let formatter = annual.storeProduct.priceFormatter ?? NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = annual.storeProduct.priceFormatter?.locale ?? Locale.current
        return formatter.string(from: monthlyPrice as NSDecimalNumber)
    }

    static func annualSavingsBadge(monthly: Package?, annual: Package?) -> String? {
        guard let monthly, let annual else { return nil }

        let monthlyAnnualized = monthly.storeProduct.price * 12
        let annualPrice = annual.storeProduct.price
        guard monthlyAnnualized > 0, annualPrice > 0, annualPrice < monthlyAnnualized else { return nil }

        let savingsPercent = (
            (monthlyAnnualized - annualPrice) / monthlyAnnualized * 100 as NSDecimalNumber
        ).doubleValue
        let rounded = Int(savingsPercent.rounded())
        guard rounded > 0 else { return nil }
        return "SAVE \(rounded)%"
    }

    private static func hasActiveProEntitlement(_ info: CustomerInfo) -> Bool {
        info.entitlements[proEntitlementIdentifier]?.isActive == true
    }
}
