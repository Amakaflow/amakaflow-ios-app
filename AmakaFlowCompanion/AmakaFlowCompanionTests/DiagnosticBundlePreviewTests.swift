import XCTest
@testable import AmakaFlowCompanion

final class DiagnosticBundlePreviewTests: XCTestCase {
    func testPreviewListsExactIncludedFiles() {
        XCTAssertEqual(
            DiagnosticBundlePreview.includedFileNames,
            ["manifest.json", "status.json", "logs.ndjson", "actions.ndjson", "errors.json"]
        )
    }

    func testPreviewMetadataComesFromFrozenSnapshot() {
        var events = [
            event("oldest", at: date("2026-08-21T20:00:00Z")),
            event("newest", at: date("2026-08-21T20:15:00Z"))
        ]
        let snapshot = bundleSnapshot(events: events)

        events.append(event("live-mutation", at: date("2026-08-21T20:30:00Z")))
        let preview = DiagnosticBundlePreview(snapshot: snapshot)

        XCTAssertEqual(preview.eventCount, 2)
        XCTAssertEqual(preview.timeRange?.start, date("2026-08-21T20:00:00Z"))
        XCTAssertEqual(preview.timeRange?.end, date("2026-08-21T20:15:00Z"))
    }

    func testSnapshotCodableRoundTripPreservesStatusEventsAndActions() throws {
        let snapshot = bundleSnapshot(
            events: [event("sync.retry.failed", at: date("2026-08-21T20:02:00Z"))],
            actions: [
                DiagnosticActionSnapshot(
                    id: "action-1",
                    timestamp: date("2026-08-21T20:03:00Z"),
                    capability: .syncRetry,
                    outcome: .failed,
                    title: "Retry sync",
                    safeContext: ["pending_count": "2"],
                    requestID: "req-action-1",
                    sentryEventID: "sentry-action-1"
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(DiagnosticBundleSnapshot.self, from: encoder.encode(snapshot))

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.status.results.first?.id, .grantState)
        XCTAssertEqual(decoded.events.first?.name, "sync.retry.failed")
        XCTAssertEqual(decoded.actions.first?.capability, .syncRetry)
    }

    func testSnapshotUsesValueSemanticsForCallerOwnedArrays() {
        var events = [event("original", at: date("2026-08-21T20:00:00Z"))]
        var actions = [
            DiagnosticActionSnapshot(
                id: "action-original",
                timestamp: date("2026-08-21T20:01:00Z"),
                capability: .cacheClearSafe,
                outcome: .succeeded,
                title: "Clear safe cache",
                safeContext: [:],
                requestID: nil,
                sentryEventID: nil
            )
        ]
        let snapshot = bundleSnapshot(events: events, actions: actions)

        events[0] = event("mutated", at: date("2026-08-21T20:10:00Z"))
        actions[0] = DiagnosticActionSnapshot(
            id: "action-mutated",
            timestamp: date("2026-08-21T20:11:00Z"),
            capability: .syncRetry,
            outcome: .failed,
            title: "Mutated",
            safeContext: ["ignored": "true"],
            requestID: "req-mutated",
            sentryEventID: nil
        )

        XCTAssertEqual(snapshot.events.map(\.name), ["original"])
        XCTAssertEqual(snapshot.actions.map(\.id), ["action-original"])
    }

    func testLogsPolicyExposesNoEventContentWithoutLogsCapability() {
        let sensitiveEvent = event("auth.error", at: date("2026-08-21T20:00:00Z"), message: "safe auth failure")

        let visible = DiagnosticLogsPolicy.visibleEvents(
            state: .authorized(authorization(capabilities: [.statusRead])),
            events: [sensitiveEvent]
        )

        XCTAssertEqual(visible, [])
    }

    func testLogsPolicyExposesRedactedStructuredEventsWithLogsCapability() {
        let event = event(
            "api.request.failed",
            at: date("2026-08-21T20:00:00Z"),
            message: "HTTP 500 response omitted from diagnostics",
            metadata: ["Endpoint": "/v1/workouts", "Status": "500"],
            requestID: "req-log-1",
            sentryEventID: "sentry-log-1"
        )

        let visible = DiagnosticLogsPolicy.visibleEvents(
            state: .authorized(authorization(capabilities: [.logsRead])),
            events: [event]
        )

        XCTAssertEqual(visible.first?.name, "api.request.failed")
        XCTAssertEqual(visible.first?.metadata["Status"], "500")
        XCTAssertEqual(visible.first?.requestID, "req-log-1")
        XCTAssertEqual(visible.first?.sentryEventID, "sentry-log-1")
    }

    func testPreviewPolicyClearsContentWhenAuthorizationIsLost() {
        let snapshot = bundleSnapshot(events: [event("queued", at: date("2026-08-21T20:00:00Z"))])

        XCTAssertNotNil(DiagnosticBundlePreviewPolicy.preview(
            state: .authorized(authorization(capabilities: [.bundleExport])),
            snapshot: snapshot
        ))
        XCTAssertNil(DiagnosticBundlePreviewPolicy.preview(state: .locked(.expired), snapshot: snapshot))
        XCTAssertNil(DiagnosticBundlePreviewPolicy.preview(
            state: .authorized(authorization(capabilities: [.logsRead])),
            snapshot: snapshot
        ))
    }

    func testPreviewListsExplicitForbiddenCategories() {
        XCTAssertEqual(
            DiagnosticBundleExcludedCategory.allCases.map(\.displayName),
            [
                "Tokens, auth headers, and cookies",
                "Request and response bodies",
                "Database dumps and rows",
                "Health samples and values",
                "Exact locations",
                "Unrelated customer content"
            ]
        )
    }

    private func bundleSnapshot(
        events: [DiagnosticEvent] = [],
        actions: [DiagnosticActionSnapshot] = []
    ) -> DiagnosticBundleSnapshot {
        DiagnosticBundleSnapshot(
            createdAt: date("2026-08-21T20:05:00Z"),
            authorization: DiagnosticBundleAuthorizationSnapshot(
                grantID: UUID(uuidString: "3b48344d-3d70-4e36-8750-e3caa43f97dc")!,
                role: .viewer,
                capabilities: [.statusRead, .logsRead, .bundleExport],
                expiresAt: date("2026-08-22T20:00:00Z")
            ),
            status: SupportDiagnosticsSnapshot(
                generatedAt: date("2026-08-21T20:04:00Z"),
                results: [
                    SupportDiagnosticsProbeResult(
                        id: .grantState,
                        title: "Grant",
                        availability: .available(fields: [.init(label: "Role", value: "viewer")])
                    )
                ]
            ),
            events: events,
            actions: actions
        )
    }

    private func event(
        _ name: String,
        at timestamp: Date,
        message: String = "safe message",
        metadata: [String: String] = [:],
        requestID: String? = nil,
        sentryEventID: String? = nil
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            id: "event-\(name)",
            timestamp: timestamp,
            severity: .warning,
            category: .sync,
            name: name,
            title: name,
            message: message,
            metadata: metadata,
            requestID: requestID,
            sentryEventID: sentryEventID,
            sentryTraceID: nil,
            accountHash: "sha256:account"
        )
    }

    private func authorization(
        capabilities: Set<SupportDiagnosticsCapability>
    ) -> SupportDiagnosticsAuthorization {
        SupportDiagnosticsAuthorization(
            grantID: UUID(uuidString: "3b48344d-3d70-4e36-8750-e3caa43f97dc")!,
            role: .viewer,
            capabilities: capabilities,
            expiresAt: date("2026-08-22T20:00:00Z"),
            serverTime: date("2026-08-21T20:00:00Z")
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
