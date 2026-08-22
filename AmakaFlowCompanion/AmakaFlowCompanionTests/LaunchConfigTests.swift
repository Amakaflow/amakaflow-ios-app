#if DEBUG
import XCTest
@testable import AmakaFlowCompanion

/// AMA-2502. The delivery mechanism is the point: Maestro passes launch
/// arguments (argv + app defaults), XCUITest passes `launchEnvironment`
/// (process environment only). A decoder that reads one source silently
/// disables every flow that uses the other.
final class LaunchConfigTests: XCTestCase {

    private struct Defaults: LaunchDefaultsReading {
        var values: [String: String] = [:]
        func string(forKey key: String) -> String? { values[key] }
    }

    private func decode(
        argv: [String] = [],
        defaults: [String: String] = [:],
        environment: [String: String] = [:]
    ) -> LaunchConfig? {
        LaunchConfig.decode(
            argv: argv,
            defaults: Defaults(values: defaults),
            environment: environment
        )
    }

    // MARK: - Delivery mechanisms

    func testNoFlagsMeansNormalLaunch() {
        XCTAssertNil(decode(argv: ["/path/to/App"]))
    }

    func testEachDeliveryMechanismEnablesFixturesOnItsOwn() {
        let cases: [(String, LaunchConfig?)] = [
            ("argv", decode(argv: ["-AF_USE_FIXTURES", "true"])),
            ("bare argv", decode(argv: ["AF_USE_FIXTURES", "true"])),
            ("defaults", decode(defaults: ["AF_USE_FIXTURES": "true"])),
            ("dashed defaults", decode(defaults: ["-AF_USE_FIXTURES": "true"])),
            ("environment", decode(environment: ["AF_USE_FIXTURES": "true"]))
        ]
        for (name, config) in cases {
            XCTAssertEqual(config?.useFixtures, true, "\(name) should enable fixtures")
        }
    }

    func testTruthinessAcceptsTrueOneAndYesCaseInsensitively() {
        for raw in ["true", "TRUE", "1", "yes", "YES"] {
            XCTAssertEqual(
                decode(environment: ["AF_SKIP_ONBOARDING": raw])?.skipOnboarding,
                true,
                "\(raw) should be truthy"
            )
        }
        for raw in ["false", "0", "no", "", "maybe"] {
            XCTAssertNotEqual(
                decode(environment: ["AF_SKIP_ONBOARDING": raw])?.skipOnboarding,
                true,
                "\(raw) should not be truthy"
            )
        }
    }

    func testBareFlagFollowedByAnotherFlagCountsAsEnabled() {
        let config = decode(argv: ["-AF_USE_FIXTURES", "-AF_SKIP_ONBOARDING", "true"])
        XCTAssertEqual(config?.useFixtures, true)
        XCTAssertEqual(config?.skipOnboarding, true)
    }

    func testTrailingBareFlagCountsAsEnabled() {
        XCTAssertEqual(decode(argv: ["-AF_USE_FIXTURES"])?.useFixtures, true)
    }

    // MARK: - Precedence

    func testLaunchArgumentsWinOverStaleSimulatorEnvironment() {
        let config = decode(
            argv: ["-AF_USE_FIXTURES", "true"],
            environment: ["AF_USE_FIXTURES": "false"]
        )
        XCTAssertEqual(config?.useFixtures, true)
    }

    func testAppDefaultsWinOverStaleSimulatorEnvironment() {
        let config = decode(
            defaults: ["AF_USE_FIXTURES": "true"],
            environment: ["AF_USE_FIXTURES": "false"]
        )
        XCTAssertEqual(config?.useFixtures, true)
    }

    func testEmptyDefaultsValueFallsThroughToEnvironment() {
        let config = decode(
            defaults: ["AF_USE_FIXTURES": ""],
            environment: ["AF_USE_FIXTURES": "true"]
        )
        XCTAssertEqual(config?.useFixtures, true)
    }

    // MARK: - Session

    func testLegacyBooleanSessionForm() {
        let config = decode(environment: ["AF_SESSION_IDENTITY": "true"])
        XCTAssertEqual(config?.session, .legacyBoolean)
        let identity = config?.session?.identity
        XCTAssertEqual(identity?.userID, "user_uitest_ama1843")
        XCTAssertEqual(identity?.email, "claude+clerk_test@amakaflow.dev")
        XCTAssertEqual(identity?.displayName, "UITest User")
    }

    func testCommaPayloadSessionForm() {
        let config = decode(argv: [
            "-AF_SESSION_IDENTITY",
            "user_id=user_ama2383_ai,email=claude+clerk_test@amakaflow.dev,name=AMA2383 AI"
        ])
        XCTAssertEqual(
            config?.session,
            .identity(
                userID: "user_ama2383_ai",
                email: "claude+clerk_test@amakaflow.dev",
                displayName: "AMA2383 AI"
            )
        )
    }

    func testPartialPayloadFallsBackToSyntheticIdentity() {
        let identity = decode(environment: ["AF_SESSION_IDENTITY": "user_id=only_id"])?
            .session?.identity
        XCTAssertEqual(identity?.userID, "only_id")
        XCTAssertEqual(identity?.email, "claude+clerk_test@amakaflow.dev")
        XCTAssertEqual(identity?.displayName, "UITest User")
    }

    func testRealClerkSessionWinsOverMockSession() {
        let config = decode(environment: [
            "AF_SESSION_IDENTITY": "true",
            "AF_SESSION_CLERK_EMAIL": "claude+clerk_test@amakaflow.dev",
            "AF_CLERK_PASSWORD": "hunter2"
        ])
        XCTAssertEqual(
            config?.session,
            .realClerk(email: "claude+clerk_test@amakaflow.dev", password: "hunter2")
        )
        XCTAssertEqual(config?.realClerkEmail, "claude+clerk_test@amakaflow.dev")
    }

    /// Every XCUITest supplies this triple and no real-session email, so
    /// `clerkTestUser` must not be derived from `session`.
    func testClerkTestUserNeedsAllThreeCredentialsAndNoSession() {
        let config = decode(environment: [
            "AF_CLERK_EMAIL": "claude+clerk_test@amakaflow.dev",
            "AF_CLERK_PASSWORD": "hunter2",
            "AF_CLERK_PUBLISHABLE_KEY": "pk_test_x"
        ])
        XCTAssertEqual(config?.clerkTestUser, true)
        XCTAssertNil(config?.session)

        XCTAssertNotEqual(
            decode(environment: [
                "AF_CLERK_EMAIL": "claude+clerk_test@amakaflow.dev",
                "AF_CLERK_PASSWORD": "hunter2"
            ])?.clerkTestUser,
            true
        )
    }

    // MARK: - Fixtures and faults

    func testFixtureNamesSplitOnCommas() {
        XCTAssertEqual(
            decode(environment: ["AF_FIXTURE_NAMES": " strength_block_w1 , emom_strength "])?.fixtures,
            .named(["strength_block_w1", "emom_strength"])
        )
        XCTAssertEqual(decode(environment: ["AF_USE_FIXTURES": "true"])?.fixtures, .all)
    }

    func testEmptyLibraryScenario() {
        XCTAssertEqual(decode(environment: ["AF_FIXTURE_STATE": "empty"])?.isLibraryEmpty, true)
    }

    /// Stale simulator env must not empty a dogfood launch that named fixtures.
    func testNamedFixturesIgnoreStaleEmptyStateFromEnvironment() {
        let config = decode(
            argv: ["-AF_FIXTURE_NAMES", "strength_block_w1"],
            environment: ["AF_FIXTURE_STATE": "empty"]
        )
        XCTAssertNotEqual(config?.isLibraryEmpty, true)
    }

    func testWatchManagerDemoAndReplaceFaultsCoexist() {
        let config = decode(environment: [
            "AF_DEMO_WATCH_MANAGER": "true",
            "AF_FAULT_WATCH_REPLACE_FAIL": "1",
            "AF_FAULT_WATCH_REPLACE_DELAY_MS": "1500"
        ])
        XCTAssertEqual(config?.isWatchManagerDemo, true)
        XCTAssertEqual(config?.watchItemReplaceFails, true)
        XCTAssertEqual(config?.watchItemReplaceDelayMilliseconds, 1500)
    }

    func testGarminFaults() {
        XCTAssertEqual(decode(environment: ["AF_FAULT_GARMIN_PAIRED": "1"])?.isGarminPaired, true)
        XCTAssertEqual(
            decode(environment: ["AF_FAULT_GARMIN_PUSH_FAIL": " watch_full "])?.garminPushFailureReason,
            "watch_full"
        )
    }

    // MARK: - Demo hosts

    func testActualsDogfoodHostFromAnyOfItsThreeFlags() {
        for flag in ["AF_DEMO_ACTUALS_HUB"] {
            XCTAssertEqual(
                decode(environment: [flag: "true"])?.demoHost,
                .actualsDogfood(autorun: nil),
                "\(flag) should open the dogfood hub"
            )
        }
    }

    func testActualsDogfoodAutorunModes() {
        let expected: [(String, LaunchConfig.AutorunMode)] = [
            ("live", .live),
            ("companion", .companion),
            ("fixture", .fixture),
            ("walkthrough", .walkthrough)
        ]
        for (raw, mode) in expected {
            XCTAssertEqual(
                decode(environment: ["AF_DEMO_ACTUALS_HUB": "true", "AF_DEMO_AUTORUN": raw])?.demoHost,
                .actualsDogfood(autorun: mode),
                "AF_DEMO_AUTORUN=\(raw)"
            )
        }
    }

    func testUnknownAutorunValueIsNotAMode() {
        XCTAssertEqual(
            decode(environment: ["AF_DEMO_ACTUALS_HUB": "true", "AF_DEMO_AUTORUN": "nonsense"])?.demoHost,
            .actualsDogfood(autorun: nil)
        )
    }

    func testCreateWithAIGeneratingHost() {
        XCTAssertEqual(
            decode(environment: ["AF_DEMO_CREATE_WITH_AI": "true"])?.demoHost,
            .createWithAIGenerating
        )
    }

    func testActualsTodayDemoIsNotAHost() {
        let config = decode(environment: ["AF_DEMO_ACTUALS_TODAY": "true"])
        XCTAssertEqual(config?.actualsTodayDemo, true)
        XCTAssertNil(config?.demoHost)
    }

    // MARK: - Misc

    func testSkipAppleWatchIsSetByEitherFlag() {
        XCTAssertEqual(decode(environment: ["AF_SKIP_APPLE_WATCH": "true"])?.skipAppleWatch, true)
    }

    func testSimulationSpeedRejectsNonPositiveAndUnparseableValues() {
        XCTAssertEqual(decode(environment: ["AF_SIM_SPEED": "2.5"])?.simulationSpeed, 2.5)
        for raw in ["0", "-1", "fast"] {
            XCTAssertNil(decode(environment: ["AF_SIM_SPEED": raw]), "\(raw) should not activate")
        }
    }

    func testFixtureStateErrorDecodesToLibraryLoadFailure() {
        let config = decode(
            argv: ["app", "-AF_USE_FIXTURES", "true", "-AF_FIXTURE_STATE", "error"]
        )
        XCTAssertEqual(config?.libraryLoadFails, true)
        XCTAssertEqual(config?.isLibraryEmpty, false)
    }

    func testFixtureStateEmptyAndErrorAreDistinct() {
        let empty = decode(
            argv: ["app", "-AF_USE_FIXTURES", "true", "-AF_FIXTURE_STATE", "empty"]
        )
        XCTAssertEqual(empty?.isLibraryEmpty, true)
        XCTAssertEqual(empty?.libraryLoadFails, false)
    }
}
#endif
