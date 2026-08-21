#if DEBUG
import Foundation

/// Every UI-test and dogfood switch the app understands, decoded once at launch.
///
/// The type this replaces resolved ~15 string flags lazily at 49 call sites,
/// each re-reading launch arguments, then app defaults, then process
/// environment. Nothing decided the configuration, so "what state is the app
/// in" had no single answer.
///
/// `nil` means a normal app launch. There is no `#else` stub: a call site that
/// escapes `#if DEBUG` fails to compile rather than leaking into Release.
struct LaunchConfig: Equatable, Sendable {
    /// Harness setup. 26 of 36 Maestro flows set these four identically, so
    /// they are fields rather than scenario cases.
    var useFixtures: Bool
    var skipOnboarding: Bool
    var skipAppleWatch: Bool
    var session: TestSession?

    /// `AF_CLERK_EMAIL` + `_PASSWORD` + `_PUBLISHABLE_KEY` all present.
    /// Distinct from `session`: every XCUITest supplies this triple and no
    /// `AF_SESSION_CLERK_EMAIL`, so it cannot be derived from
    /// `session == .realClerk` without disabling the whole XCUITest suite.
    var clerkTestUser: Bool

    /// Bundled JSON filenames. An open set, so not an enum.
    var fixtures: FixtureSelection

    /// Scenario variance. A set, not one case: the watch-manager demo runs
    /// *with* a forced replace failure and a replace delay at the same time.
    var faults: Set<FaultScenario>

    /// Debug hosts that replace the root view outright.
    var demoHost: DemoHost?

    /// Seeds Actuals cards on the real Today screen. Not a host — it decorates
    /// production content rather than replacing the root view.
    var actualsTodayDemo: Bool

    var simulationSpeed: Double

    /// 24 distinct payloads across the flows, in two incompatible formats.
    enum TestSession: Equatable, Sendable {
        case legacyBoolean
        case identity(userID: String?, email: String, displayName: String?)
        case realClerk(email: String, password: String?)
    }

    enum FixtureSelection: Equatable, Sendable {
        case all
        case named([String])
    }

    enum FaultScenario: Hashable, Sendable {
        case emptyLibrary
        case libraryLoadFails
        case garminPaired
        case garminPushFails(reason: String)
        case watchItemReplaceFails
        case watchItemReplaceSlow(milliseconds: Int)
        case watchManagerDemo
    }

    enum DemoHost: Equatable, Sendable {
        case createWithAIGenerating
        case actualsDogfood(autorun: AutorunMode?)
    }

    enum AutorunMode: Equatable, Sendable {
        case live
        case companion
        case fixture
        case walkthrough
    }

    /// AMA-1843 payload fields are optional and fall back to a synthetic identity.
    struct TestIdentity: Equatable, Sendable {
        var userID: String
        var email: String
        var displayName: String
    }

    /// Decoded once, at first access, from a snapshot of all three delivery
    /// mechanisms. All three are load-bearing and none may be dropped:
    /// Maestro passes `launchApp.arguments`, which iOS surfaces as argv and as
    /// app-defaults keys; every XCUITest passes `launchEnvironment`, which
    /// arrives only as process environment. A decoder reading argv alone would
    /// silently disable every XCUITest flow in the repo.
    ///
    /// Argument order is deliberate: a stale simulator environment must never
    /// shadow an intentional launch.
    static let active: LaunchConfig? = live()

    /// Fresh decode. Maestro's launch arguments are not always visible on the
    /// first read, so the Clerk password poll re-reads rather than caching.
    static func live() -> LaunchConfig? {
        decode(
            argv: ProcessInfo.processInfo.arguments,
            defaults: UserDefaults.standard,
            environment: ProcessInfo.processInfo.environment
        )
    }

    /// Pure, so the whole matrix is table-testable without a simulator. This is
    /// what AMA-2457 asked for when it wanted the delivery mechanism verified
    /// rather than documented in a comment.
    static func decode(
        argv: [String],
        defaults: LaunchDefaultsReading,
        environment: [String: String]
    ) -> LaunchConfig? {
        let source = Source(argv: argv, defaults: defaults, environment: environment)

        let fixtureNames = source.list(for: "AF_FIXTURE_NAMES")
        var faults: Set<FaultScenario> = []
        switch source.fixtureState(hasFixtureNames: fixtureNames != nil) {
        case "empty": faults.insert(.emptyLibrary)
        case "error": faults.insert(.libraryLoadFails)
        default: break
        }
        if source.isTruthy("AF_FAULT_GARMIN_PAIRED") {
            faults.insert(.garminPaired)
        }
        if let reason = source.value(for: "AF_FAULT_GARMIN_PUSH_FAIL")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            faults.insert(.garminPushFails(reason: reason))
        }
        if source.isTruthy("AF_FAULT_WATCH_REPLACE_FAIL") {
            faults.insert(.watchItemReplaceFails)
        }
        if let raw = source.value(for: "AF_FAULT_WATCH_REPLACE_DELAY_MS"),
           let milliseconds = Int(raw) {
            faults.insert(.watchItemReplaceSlow(milliseconds: milliseconds))
        }
        if source.isTruthy("AF_DEMO_WATCH_MANAGER") || source.isTruthy("AF_DEMO_WATCH_MANAGER") {
            faults.insert(.watchManagerDemo)
        }

        let config = LaunchConfig(
            useFixtures: source.isTruthy("AF_USE_FIXTURES"),
            skipOnboarding: source.isTruthy("AF_SKIP_ONBOARDING"),
            skipAppleWatch: source.isTruthy("AF_SKIP_APPLE_WATCH")
,
            session: source.session(),
            clerkTestUser: source.hasClerkTestUser(),
            fixtures: fixtureNames.map(FixtureSelection.named) ?? .all,
            faults: faults,
            demoHost: source.demoHost(),
            actualsTodayDemo: source.isTruthy("AF_DEMO_ACTUALS_TODAY"),
            simulationSpeed: source.simulationSpeed()
        )
        return config == .inactive ? nil : config
    }

    private static let inactive = LaunchConfig(
        useFixtures: false,
        skipOnboarding: false,
        skipAppleWatch: false,
        session: nil,
        clerkTestUser: false,
        fixtures: .all,
        faults: [],
        demoHost: nil,
        actualsTodayDemo: false,
        simulationSpeed: 1.0
    )
}

// MARK: - Fault lookups

extension LaunchConfig {
    var isLibraryEmpty: Bool { faults.contains(.emptyLibrary) }
    var libraryLoadFails: Bool { faults.contains(.libraryLoadFails) }
    var isGarminPaired: Bool { faults.contains(.garminPaired) }
    var isWatchManagerDemo: Bool { faults.contains(.watchManagerDemo) }
    var watchItemReplaceFails: Bool { faults.contains(.watchItemReplaceFails) }

    var garminPushFailureReason: String? {
        for case .garminPushFails(let reason) in faults { return reason }
        return nil
    }

    var watchItemReplaceDelayMilliseconds: Int? {
        for case .watchItemReplaceSlow(let milliseconds) in faults { return milliseconds }
        return nil
    }

    var fixtureNames: [String]? {
        if case .named(let names) = fixtures { return names }
        return nil
    }

    var clerkPassword: String? {
        if case .realClerk(_, let password) = session { return password }
        return nil
    }

    var realClerkEmail: String? {
        if case .realClerk(let email, _) = session { return email }
        return nil
    }
}

// MARK: - Delivery mechanisms

/// Seam so `decode` stays pure in tests. `UserDefaults` conforms directly.
protocol LaunchDefaultsReading {
    func string(forKey key: String) -> String?
}

extension UserDefaults: LaunchDefaultsReading {}

private struct Source {
    let argv: [String]
    let defaults: LaunchDefaultsReading
    let environment: [String: String]

    /// `simctl launch … -FLAG true` sometimes drops the value token; a bare
    /// `-FLAG` followed by another `-Next` still means the flag was requested.
    func argument(for key: String) -> String? {
        for index in argv.indices {
            let token = argv[index]
            guard token == key || token == "-\(key)" else { continue }
            let next = index + 1
            if next < argv.count, !argv[next].hasPrefix("-") {
                return argv[next]
            }
            return "true"
        }
        return nil
    }

    /// Prefer explicit launch arguments / app defaults over the simulator's
    /// process environment — stale `simctl`/scheme env (e.g.
    /// `AF_USE_FIXTURES=false`) otherwise shadows intentional dogfood launches.
    func value(for key: String) -> String? {
        if let fromArgs = argument(for: key) {
            return fromArgs
        }
        if let stored = defaults.string(forKey: key), !stored.isEmpty {
            return stored
        }
        if let stored = defaults.string(forKey: "-\(key)"), !stored.isEmpty {
            return stored
        }
        if let env = environment[key], !env.isEmpty {
            return env
        }
        return nil
    }

    func isTruthy(_ key: String) -> Bool {
        guard let raw = value(for: key)?.lowercased() else { return false }
        return raw == "true" || raw == "1" || raw == "yes"
    }

    func list(for key: String) -> [String]? {
        guard let raw = value(for: key), !raw.isEmpty else { return nil }
        let names = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }

    /// Ignore stale simulator env `empty` when launch args/defaults name fixtures —
    /// otherwise dogfood launches load zero workouts while Library still looks "live".
    func fixtureState(hasFixtureNames: Bool) -> String? {
        if let fromArgs = argument(for: "AF_FIXTURE_STATE") {
            return fromArgs.isEmpty ? nil : fromArgs
        }
        if let stored = defaults.string(forKey: "AF_FIXTURE_STATE"), !stored.isEmpty {
            return stored
        }
        if hasFixtureNames {
            return nil
        }
        let state = environment["AF_FIXTURE_STATE"]
        return state?.isEmpty == false ? state : nil
    }

    /// The real-Clerk bypass wins: `AuthViewModel.start()` checks it first and
    /// returns before the mock bypass can run.
    func session() -> LaunchConfig.TestSession? {
        if let email = value(for: "AF_SESSION_CLERK_EMAIL"), !email.isEmpty {
            return .realClerk(email: email, password: value(for: "AF_CLERK_PASSWORD"))
        }
        guard let raw = value(for: "AF_SESSION_IDENTITY"), !raw.isEmpty else { return nil }
        var fields: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                fields[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        guard !fields.isEmpty else { return .legacyBoolean }
        return .identity(
            userID: fields["user_id"],
            email: fields["email"] ?? LaunchConfig.TestSession.defaultEmail,
            displayName: fields["name"]
        )
    }

    func hasClerkTestUser() -> Bool {
        value(for: "AF_CLERK_EMAIL")?.isEmpty == false
            && value(for: "AF_CLERK_PASSWORD")?.isEmpty == false
            && value(for: "AF_CLERK_PUBLISHABLE_KEY")?.isEmpty == false
    }

    func demoHost() -> LaunchConfig.DemoHost? {
        if isTruthy("AF_DEMO_ACTUALS_HUB") {
            return .actualsDogfood(autorun: autorun())
        }
        if isTruthy("AF_DEMO_CREATE_WITH_AI") {
            return .createWithAIGenerating
        }
        return nil
    }

    private func autorun() -> LaunchConfig.AutorunMode? {
        if isTruthy("AMA2426_AUTORUN") {
            if isTruthy("AMA2426_LIVE") { return .live }
            if isTruthy("AMA2426_COMPANION") { return .companion }
            return .fixture
        }
        if isTruthy("AMA2387_AUTORUN") { return .walkthrough }
        return nil
    }

    func simulationSpeed() -> Double {
        guard let raw = value(for: "AF_SIM_SPEED"), let speed = Double(raw), speed > 0 else {
            return 1.0
        }
        return speed
    }
}

extension LaunchConfig.TestSession {
    static let defaultUserID = "user_uitest_ama1843"
    static let defaultEmail = "claude+clerk_test@amakaflow.dev"
    static let defaultDisplayName = "UITest User"

    var identity: LaunchConfig.TestIdentity {
        switch self {
        case .legacyBoolean, .realClerk:
            return LaunchConfig.TestIdentity(
                userID: Self.defaultUserID,
                email: Self.defaultEmail,
                displayName: Self.defaultDisplayName
            )
        case .identity(let userID, let email, let displayName):
            return LaunchConfig.TestIdentity(
                userID: userID ?? Self.defaultUserID,
                email: email,
                displayName: displayName ?? Self.defaultDisplayName
            )
        }
    }
}
#endif
