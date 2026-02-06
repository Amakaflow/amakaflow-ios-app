import XCTest
@testable import AmakaFlowCompanion

final class TestAuthStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear any launch argument defaults before each test
        let keys = [
            "UITEST_AUTH_SECRET", "UITEST_USER_ID", "UITEST_USER_EMAIL",
            "UITEST_USE_FIXTURES", "UITEST_FIXTURES", "UITEST_FIXTURE_STATE",
            "UITEST_SKIP_ONBOARDING", "UITEST_MODE"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Also clear stored credential keys
        UserDefaults.standard.removeObject(forKey: "e2e_test_auth_secret")
        UserDefaults.standard.removeObject(forKey: "e2e_test_user_id")
        UserDefaults.standard.removeObject(forKey: "e2e_test_user_email")
    }

    func testUseFixturesReadsFromUserDefaults() {
        UserDefaults.standard.set("true", forKey: "UITEST_USE_FIXTURES")
        XCTAssertTrue(TestAuthStore.shared.useFixtures)
    }

    func testFixtureNamesReadsFromUserDefaults() {
        UserDefaults.standard.set("amrap_10min,strength_block_w1", forKey: "UITEST_FIXTURES")
        let names = TestAuthStore.shared.fixtureNames
        XCTAssertEqual(names, ["amrap_10min", "strength_block_w1"])
    }

    func testFixtureStateReadsFromUserDefaults() {
        UserDefaults.standard.set("empty", forKey: "UITEST_FIXTURE_STATE")
        XCTAssertEqual(TestAuthStore.shared.fixtureState, "empty")
    }

    func testSkipOnboardingReadsFromUserDefaults() {
        UserDefaults.standard.set("true", forKey: "UITEST_SKIP_ONBOARDING")
        XCTAssertTrue(TestAuthStore.shared.skipOnboarding)
    }

    func testAuthSecretReadsFromUserDefaults() {
        UserDefaults.standard.set("test-secret-123", forKey: "UITEST_AUTH_SECRET")
        XCTAssertEqual(TestAuthStore.shared.authSecret, "test-secret-123")
    }

    func testUserIdReadsFromUserDefaults() {
        UserDefaults.standard.set("test-user-456", forKey: "UITEST_USER_ID")
        XCTAssertEqual(TestAuthStore.shared.userId, "test-user-456")
    }

    func testUserEmailReadsFromUserDefaults() {
        UserDefaults.standard.set("test@example.com", forKey: "UITEST_USER_EMAIL")
        XCTAssertEqual(TestAuthStore.shared.userEmail, "test@example.com")
    }
}
