import XCTest
@testable import AmakaFlowCompanion

final class SupportDiagnosticsProbeTests: XCTestCase {
    func testRunnerKeepsSiblingResultWhenOneProbeThrowsSafeError() async {
        let runner = SupportDiagnosticsProbeRunner(
            probes: [
                StubDiagnosticsProbe(
                    id: .appBuildDevice,
                    title: "App",
                    outcome: .success([.init(label: "Version", value: "1.2.3")])
                ),
                StubDiagnosticsProbe(
                    id: .databaseHealth,
                    title: "Database",
                    outcome: .failure(.init(code: .databaseUnavailable, correlationID: "req-db-1"))
                )
            ],
            now: { Self.fixedDate }
        )

        let snapshot = await runner.run()

        XCTAssertEqual(snapshot.generatedAt, Self.fixedDate)
        XCTAssertEqual(snapshot.results.map(\.id), [.appBuildDevice, .databaseHealth])
        XCTAssertEqual(
            snapshot.result(for: .appBuildDevice)?.availability,
            .available(fields: [.init(label: "Version", value: "1.2.3")])
        )
        XCTAssertEqual(
            snapshot.result(for: .databaseHealth)?.availability,
            .unavailable(errorCode: .databaseUnavailable, correlationID: "req-db-1")
        )
    }

    func testRunnerTurnsOnlyTimedOutProbeUnavailable() async {
        SupportDiagnosticsRuntimeState.shared.resetForTests()
        SupportDiagnosticsRuntimeState.shared.setFallbackCorrelationIDForTests("diag-fixed-default")
        defer { SupportDiagnosticsRuntimeState.shared.resetForTests() }

        let runner = SupportDiagnosticsProbeRunner(
            probes: [
                StubDiagnosticsProbe(
                    id: .reachabilityHealth,
                    title: "Reachability",
                    timeout: .milliseconds(20),
                    outcome: .sleepThenSuccess(.seconds(5))
                ),
                StubDiagnosticsProbe(
                    id: .watchConnectivity,
                    title: "Watch",
                    outcome: .success([.init(label: "Reachable", value: "Yes")])
                )
            ],
            now: { Self.fixedDate }
        )

        let snapshot = await runner.run()

        XCTAssertEqual(
            snapshot.result(for: .reachabilityHealth)?.availability,
            .unavailable(errorCode: .probeTimedOut, correlationID: "diag-fixed-default")
        )
        XCTAssertEqual(
            snapshot.result(for: .watchConnectivity)?.availability,
            .available(fields: [.init(label: "Reachable", value: "Yes")])
        )
    }

    func testRunnerHardTimeoutCatchesCancellationUnawareProbeMutation() async {
        let runner = SupportDiagnosticsProbeRunner(
            probes: [
                StubDiagnosticsProbe(
                    id: .reachabilityHealth,
                    title: "Cancellation-unaware reachability",
                    timeout: .milliseconds(20),
                    outcome: .blockingThenSuccess(0.25)
                ),
                StubDiagnosticsProbe(
                    id: .watchConnectivity,
                    title: "Watch",
                    outcome: .success([.init(label: "Reachable", value: "Yes")])
                )
            ],
            now: { Self.fixedDate },
            correlationIDProvider: { "safe-timeout-correlation" }
        )

        let clock = ContinuousClock()
        let started = clock.now
        let snapshot = await runner.run()
        let elapsed = started.duration(to: clock.now)

        XCTAssertLessThan(
            elapsed,
            .milliseconds(200),
            "The runner must return comfortably before the 250 ms cancellation-unaware probe completes"
        )
        XCTAssertEqual(
            snapshot.result(for: .reachabilityHealth)?.availability,
            .unavailable(errorCode: .probeTimedOut, correlationID: "safe-timeout-correlation")
        )
        XCTAssertEqual(
            snapshot.result(for: .watchConnectivity)?.availability,
            .available(fields: [.init(label: "Reachable", value: "Yes")])
        )
    }

    func testRunnerInjectsSafeCorrelationIDForGenericFailuresAndTimeoutsMutation() async {
        let runner = SupportDiagnosticsProbeRunner(
            probes: [
                StubDiagnosticsProbe(
                    id: .databaseHealth,
                    title: "Database",
                    outcome: .genericFailure
                ),
                StubDiagnosticsProbe(
                    id: .queues,
                    title: "Queues",
                    timeout: .milliseconds(20),
                    outcome: .sleepThenSuccess(.seconds(5))
                )
            ],
            now: { Self.fixedDate },
            correlationIDProvider: { "safe-runner-correlation" }
        )

        let snapshot = await runner.run()

        XCTAssertEqual(
            snapshot.result(for: .databaseHealth)?.availability,
            .unavailable(errorCode: .probeFailed, correlationID: "safe-runner-correlation")
        )
        XCTAssertEqual(
            snapshot.result(for: .queues)?.availability,
            .unavailable(errorCode: .probeTimedOut, correlationID: "safe-runner-correlation")
        )
    }

    func testDefaultRunnerCorrelationCatchesStatusViewNilCorrelationMutation() async {
        SupportDiagnosticsRuntimeState.shared.resetForTests()
        SupportDiagnosticsRuntimeState.shared.setFallbackCorrelationIDForTests("diag-fixed-default")
        defer { SupportDiagnosticsRuntimeState.shared.resetForTests() }

        let runner = SupportDiagnosticsProbeRunner(
            probes: [
                StubDiagnosticsProbe(
                    id: .databaseHealth,
                    title: "Database",
                    outcome: .genericFailure
                )
            ],
            now: { Self.fixedDate }
        )

        let snapshot = await runner.run()

        XCTAssertEqual(
            snapshot.result(for: .databaseHealth)?.availability,
            .unavailable(errorCode: .probeFailed, correlationID: "diag-fixed-default")
        )
    }

    func testActualProbeOutputsCatchStaticContractOnlyMutation() async throws {
        let clerkExpiry = Self.fixedDate.addingTimeInterval(600)
        let authorization = SupportDiagnosticsAuthorization(
            grantID: UUID(uuidString: "00000000-0000-0000-0000-000000000251")!,
            role: .staff,
            capabilities: [.statusRead, .featureOverrideAllowlisted],
            expiresAt: Self.fixedDate.addingTimeInterval(3_600),
            serverTime: Self.fixedDate
        )

        let appLabels = Set(try await AppBuildDeviceProbe().run().map(\.label))
        let clerkFields = try await ClerkSessionProbe(
            sessionState: {
                SupportDiagnosticsClerkSessionState(
                    hasResolvedInitialSession: true,
                    isAuthenticated: true,
                    hasActiveSession: true,
                    needsReauth: false,
                    tokenExpiresAt: clerkExpiry,
                    lastTokenRefresh: Self.fixedDate,
                    rawUserID: "user_live_contract"
                )
            },
            now: { Self.fixedDate }
        ).run()
        let watchFields = try await WatchConnectivityProbe(
            lastTransferState: {
                .recorded(action: "syncWorkouts", outcome: "queued")
            }
        ).run()
        let grantFields = try await GrantStateProbe(
            authorization: authorization,
            featureOverrideState: {
                .configured(["program_wizard=enabled"])
            },
            simulationState: { true }
        ).run()
        let correlationFields = try await CorrelationIDsProbe(
            provider: {
                SupportDiagnosticsCorrelationIdentifiers(
                    requestID: "req-live-1",
                    sentryEventID: "sentry-live-1",
                    sentryTraceID: "trace-live-1"
                )
            }
        ).run()

        XCTAssertTrue(appLabels.isSuperset(of: ["Distribution", "Locale", "Timezone"]))
        XCTAssertEqual(clerkFields.value(for: "Token expiry"), supportDiagnosticsFormatted(clerkExpiry))
        XCTAssertNotEqual(clerkFields.value(for: "Token expiry"), "Not reported by SDK")
        XCTAssertEqual(clerkFields.value(for: "User ID hash")?.hasPrefix("sha256:"), true)
        XCTAssertEqual(watchFields.value(for: "Last transfer result"), "syncWorkouts: queued")
        XCTAssertEqual(grantFields.value(for: "Allowlisted feature overrides"), "program_wizard=enabled")
        XCTAssertEqual(grantFields.value(for: "Simulation state"), "Enabled")
        XCTAssertEqual(correlationFields.value(for: "Existing request ID"), "req-live-1")
        XCTAssertEqual(correlationFields.value(for: "Existing Sentry event ID"), "sentry-live-1")
        XCTAssertEqual(correlationFields.value(for: "Existing Sentry trace ID"), "trace-live-1")
    }

    func testLiveDependenciesReadRuntimeStateCatchesNoneRecordedDefaultsMutation() async {
        SupportDiagnosticsRuntimeState.shared.resetForTests()
        defer { SupportDiagnosticsRuntimeState.shared.resetForTests() }
        SupportDiagnosticsRuntimeState.shared.recordRequestID("req-runtime-1")
        SupportDiagnosticsRuntimeState.shared.recordSentryEventID("sentry-runtime-1")
        SupportDiagnosticsRuntimeState.shared.recordSentryTraceID("trace-runtime-1")
        SupportDiagnosticsRuntimeState.shared.recordWatchTransfer(action: "dayStateResponse", outcome: "sent")

        let dependencies = SupportDiagnosticsProbeDependencies.live
        let identifiers = await dependencies.correlationIdentifiers()
        let watchState = await dependencies.lastWatchTransferState()

        XCTAssertEqual(identifiers.requestID, "req-runtime-1")
        XCTAssertEqual(identifiers.sentryEventID, "sentry-runtime-1")
        XCTAssertEqual(identifiers.sentryTraceID, "trace-runtime-1")
        XCTAssertEqual(watchState, .recorded(action: "dayStateResponse", outcome: "sent"))
    }

    func testAllowlistedFeatureOverrideReaderCatchesArbitraryDefaultsScanMutation() async {
        let reader = SupportDiagnosticsFeatureOverrideReader(
            environment: [
                "AMAKAFLOW_PROGRAM_WIZARD": "1",
                "AMAKAFLOW_NON_MVP": "0",
                "UNRELATED_SECRET_FLAG": "1"
            ],
            explicitStates: [
                "strength_auto_capture": true
            ]
        )

        let overrides = await reader.state()

        XCTAssertEqual(
            SupportDiagnosticsSafeSummaries.featureOverrides(overrides),
            "non_mvp=disabled, program_wizard=enabled, strength_auto_capture=enabled"
        )
    }

    func testAllowlistedFeatureOverrideReaderCatchesMissingStrengthEnvironmentOverrideMutation() async {
        let reader = SupportDiagnosticsFeatureOverrideReader(
            environment: [
                "AMAKAFLOW_STRENGTH_AUTO_CAPTURE": "1",
                "UNRELATED_SECRET_FLAG": "true"
            ],
            explicitStates: [:]
        )

        let overrides = await reader.state()

        XCTAssertEqual(
            SupportDiagnosticsSafeSummaries.featureOverrides(overrides),
            "strength_auto_capture=enabled"
        )
    }

    @MainActor
    func testApprovedReachabilityContractCatchesRemovedConfiguredAPIHealthProbeMutation() {
        let catalogueNames = supportDiagnosticsServiceEndpoints(environment: AppEnvironment.current).map(\.name)
        XCTAssertEqual(
            SupportDiagnosticsProbes.approvedReachabilityServiceNames,
            catalogueNames,
            "Configured-host and health probes must derive service names from one endpoint catalogue"
        )
    }

    func testSafeBoundaryContractCatchesRawIdentifierTokenAndMessageFieldsMutation() {
        let labels = [
            "Resolved initial session",
            "Authenticated",
            "Active SDK session",
            "Needs reauth",
            "Token expiry",
            "Last token refresh",
            "User ID hash",
            "Last transfer result",
            "Existing request ID",
            "Existing Sentry event ID",
            "Existing Sentry trace ID",
            "Allowlisted feature overrides"
        ]
        let prohibitedFragments = [
            "JWT",
            "Claims",
            "Authorization header",
            "Cookie",
            "Request body",
            "Response body",
            "Raw user ID",
            "Health sample",
            "URL query"
        ]

        for label in labels {
            for fragment in prohibitedFragments {
                XCTAssertFalse(
                    label.localizedCaseInsensitiveContains(fragment),
                    "Approved field label '\(label)' must not expose \(fragment)"
                )
            }
        }

        let hashedUserID = SupportDiagnosticsSafeSummaries.hashedUserID("user_raw_identifier")
        XCTAssertNotEqual(hashedUserID, "user_raw_identifier")
        XCTAssertTrue(hashedUserID.hasPrefix("sha256:"))
        XCTAssertFalse(hashedUserID.contains("user_raw_identifier"))

        let transferResult = SupportDiagnosticsSafeSummaries.sanitizedWatchTransferResult(
            state: .recorded(action: "syncWorkouts", outcome: "sent")
        )
        XCTAssertEqual(transferResult, "syncWorkouts: sent")
        XCTAssertFalse(transferResult.localizedCaseInsensitiveContains("heart"))
        XCTAssertFalse(transferResult.localizedCaseInsensitiveContains("body"))
    }

    func testSnapshotCodableRoundTripPreservesAvailabilityVariants() throws {
        let snapshot = SupportDiagnosticsSnapshot(
            generatedAt: Self.fixedDate,
            results: [
                SupportDiagnosticsProbeResult(
                    id: .clerkSession,
                    title: "Clerk",
                    availability: .available(fields: [.init(label: "Signed in", value: "Yes")])
                ),
                SupportDiagnosticsProbeResult(
                    id: .queues,
                    title: "Queues",
                    availability: .unavailable(errorCode: .queueUnavailable, correlationID: nil)
                )
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SupportDiagnosticsSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_777_000_000)
}

private struct StubDiagnosticsProbe: SupportDiagnosticsProbe {
    enum Outcome: Sendable {
        case success([SupportDiagnosticsDisplayField])
        case failure(SupportDiagnosticsProbeError)
        case genericFailure
        case sleepThenSuccess(Duration)
        case blockingThenSuccess(TimeInterval)
    }

    let id: SupportDiagnosticsProbeID
    let title: String
    let timeout: Duration
    let outcome: Outcome

    init(
        id: SupportDiagnosticsProbeID,
        title: String,
        timeout: Duration = .seconds(1),
        outcome: Outcome
    ) {
        self.id = id
        self.title = title
        self.timeout = timeout
        self.outcome = outcome
    }

    func run() async throws -> [SupportDiagnosticsDisplayField] {
        switch outcome {
        case .success(let fields):
            return fields
        case .failure(let error):
            throw error
        case .genericFailure:
            throw StubDiagnosticsError()
        case .sleepThenSuccess(let duration):
            try await Task.sleep(for: duration)
            return [.init(label: "Unexpected", value: "Finished")]
        case .blockingThenSuccess(let duration):
            usleep(UInt32(duration * 1_000_000))
            return [.init(label: "Unexpected", value: "Finished")]
        }
    }
}

private struct StubDiagnosticsError: Error {}

private extension Array where Element == SupportDiagnosticsDisplayField {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}
