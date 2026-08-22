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
        case sleepThenSuccess(Duration)
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
        case .sleepThenSuccess(let duration):
            try await Task.sleep(for: duration)
            return [.init(label: "Unexpected", value: "Finished")]
        }
    }
}
