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
            .unavailable(errorCode: .probeTimedOut, correlationID: nil)
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

        let started = Date()
        let snapshot = await runner.run()
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 0.15)
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

    func testApprovedLiveFieldContractCatchesRemovedDistributionLocaleTimezoneAndGrantFields() {
        let fields = SupportDiagnosticsProbes.approvedLiveFieldLabels

        XCTAssertEqual(Set(fields.keys), Set(SupportDiagnosticsProbeID.allCases))
        XCTAssertTrue(fields[.appBuildDevice, default: []].contains("Distribution"))
        XCTAssertTrue(fields[.appBuildDevice, default: []].contains("Locale"))
        XCTAssertTrue(fields[.appBuildDevice, default: []].contains("Timezone"))
        XCTAssertTrue(fields[.clerkSession, default: []].contains("Token expiry"))
        XCTAssertTrue(fields[.clerkSession, default: []].contains("User ID hash"))
        XCTAssertTrue(fields[.watchConnectivity, default: []].contains("Last transfer result"))
        XCTAssertTrue(fields[.databaseHealth, default: []].contains("Local schema version"))
        XCTAssertTrue(fields[.databaseHealth, default: []].contains("Migration health"))
        XCTAssertTrue(fields[.grantState, default: []].contains("Capability wire list"))
        XCTAssertTrue(fields[.grantState, default: []].contains("Simulation state"))
        XCTAssertTrue(fields[.grantState, default: []].contains("Allowlisted feature overrides"))
    }

    func testApprovedReachabilityContractCatchesRemovedConfiguredAPIHealthProbeMutation() {
        XCTAssertEqual(
            SupportDiagnosticsProbes.approvedReachabilityServiceNames,
            [
                "Mobile BFF",
                "Mapper API",
                "Ingestor API",
                "Calendar API",
                "Chat API",
                "MCP API",
                "Strava API"
            ]
        )
    }

    func testSafeBoundaryContractCatchesRawIdentifierTokenAndMessageFieldsMutation() {
        let labels = SupportDiagnosticsProbes.approvedLiveFieldLabels.values.flatMap { $0 }
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
