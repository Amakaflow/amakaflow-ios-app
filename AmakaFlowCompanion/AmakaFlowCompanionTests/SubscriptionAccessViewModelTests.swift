import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class MockSubscriptionBillingClient: SubscriptionBillingProviding {
    var isConfigured = true
    var hasPro = false
    var purchaseResult = true
    var restoreResult = false
    var pricing: SubscriptionPlanPricing?
    var configuredUserID: String?
    var purchaseCalls: [SubscriptionBillingPlan] = []
    var clearIdentityCalls = 0
    var syncError: Error?
    var customerHasProAccessCalls = 0

    func configure(appUserID: String?) {
        configuredUserID = appUserID
    }

    func syncAppUserID(_ appUserID: String?) async throws {
        if let syncError { throw syncError }
        configuredUserID = appUserID
    }

    func clearAppUserIdentity() async throws {
        clearIdentityCalls += 1
        configuredUserID = nil
    }

    func customerHasProAccess() async throws -> Bool {
        customerHasProAccessCalls += 1
        return hasPro
    }

    func loadPlanPricing() async throws -> SubscriptionPlanPricing? { pricing }

    func purchase(plan: SubscriptionBillingPlan) async throws -> Bool {
        purchaseCalls.append(plan)
        return purchaseResult
    }

    func restorePurchases() async throws -> Bool { restoreResult }
}

@MainActor
final class SubscriptionAccessViewModelTests: XCTestCase {
    func testRefreshUsesRevenueCatEntitlementBeforeBackend() async {
        let billing = MockSubscriptionBillingClient()
        billing.hasPro = true
        let api = MockAPIService()
        api.fetchSubscriptionResult = .failure(APIError.notImplemented)

        let viewModel = SubscriptionAccessViewModel(apiService: api, billingClient: billing)

        await viewModel.refresh()

        XCTAssertTrue(viewModel.hasProAccess)
        XCTAssertTrue(viewModel.isAccessResolved)
    }

    func testPurchaseGrantsProAccess() async {
        let billing = MockSubscriptionBillingClient()
        billing.purchaseResult = true
        let viewModel = SubscriptionAccessViewModel(billingClient: billing)

        await viewModel.purchase(plan: .monthly)

        XCTAssertTrue(viewModel.hasProAccess)
        XCTAssertEqual(billing.purchaseCalls, [.monthly])
    }

    func testRestoreWithoutSubscriptionSurfacesMessage() async {
        let billing = MockSubscriptionBillingClient()
        billing.restoreResult = false
        let viewModel = SubscriptionAccessViewModel(billingClient: billing)

        await viewModel.restorePurchases()

        XCTAssertFalse(viewModel.hasProAccess)
        XCTAssertEqual(
            viewModel.purchaseError,
            SubscriptionAccessViewModel.ErrorMessages.noActiveSubscription
        )
    }

    func testIsProSubscriptionRequiresProPlanName() {
        let activePro = Subscription(
            plan: "pro",
            status: .active,
            currentPeriodEnd: nil,
            cancelAtPeriodEnd: nil,
            features: nil
        )
        let activeStarter = Subscription(
            plan: "starter",
            status: .active,
            currentPeriodEnd: nil,
            cancelAtPeriodEnd: nil,
            features: nil
        )

        XCTAssertTrue(SubscriptionAccessViewModel.isProSubscription(activePro))
        XCTAssertFalse(SubscriptionAccessViewModel.isProSubscription(activeStarter))
    }

    func testPurchaseSurfacesIdentitySyncFailure() async {
        let billing = MockSubscriptionBillingClient()
        billing.syncError = SubscriptionBillingError.identitySyncFailed
        let viewModel = SubscriptionAccessViewModel(billingClient: billing)

        await viewModel.purchase(plan: .monthly)

        XCTAssertEqual(viewModel.purchaseError, SubscriptionBillingError.identitySyncFailed.localizedDescription)
        XCTAssertTrue(billing.purchaseCalls.isEmpty)
    }

    func testResetOnSignOutClearsBillingIdentity() async {
        let billing = MockSubscriptionBillingClient()
        billing.hasPro = true
        let viewModel = SubscriptionAccessViewModel(billingClient: billing)

        await viewModel.refresh()
        await viewModel.resetOnSignOut()

        XCTAssertEqual(billing.clearIdentityCalls, 1)
        XCTAssertNil(viewModel.planPricing)
    }

    func testRefreshSkipsBillingEntitlementWhenIdentitySyncFails() async {
        let billing = MockSubscriptionBillingClient()
        billing.hasPro = true
        billing.syncError = SubscriptionBillingError.identitySyncFailed
        let api = MockAPIService()
        api.fetchSubscriptionResult = .failure(APIError.notImplemented)

        let viewModel = SubscriptionAccessViewModel(
            apiService: api,
            billingClient: billing,
            userIdProvider: { "user-123" }
        )

        await viewModel.refresh()

        XCTAssertEqual(billing.customerHasProAccessCalls, 0)
    }
}
