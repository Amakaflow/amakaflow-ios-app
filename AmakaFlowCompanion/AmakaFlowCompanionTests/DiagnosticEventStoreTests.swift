import XCTest
@testable import AmakaFlowCompanion

final class DiagnosticEventStoreTests: DiagnosticEventStoreTestCase {
    func testMigrateLegacyDebugLogEntriesRedactsValidRecordsDeletesLegacyKeyAndSkipsMalformedData() async throws {
        let legacy = [
            DebugLogEntry(
                type: .apiError,
                title: """
                POST /v1/workouts?token=abc failed for jane@example.com \
                Bearer title-token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJsZWdhY3kifQ.signature
                """,
                details: """
                {
                  "access_token": "legacy-access-token",
                  "refresh_token": "legacy-refresh-token",
                  "profile": {"email": "jane@example.com"},
                  "customer": "raw customer support content"
                }
                """,
                metadata: [
                    "Endpoint": "/v1/workouts?token=abc",
                    "Method": "POST",
                    "Status": "500",
                    "Response": #"{"raw":"body with arbitrary customer text"}"#,
                    "request_id": "req-legacy-1"
                ]
            )
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(legacy), forKey: DefaultsKey.debugLogEntries.rawValue)

        let store = makeStore()
        try await store.migrateLegacyIfNeeded()

        let events = try await store.snapshot(.unscopedForMigrationOnly)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "api.request.failed")
        XCTAssertEqual(events[0].requestID, "req-legacy-1")
        XCTAssertEqual(events[0].metadata["Status"], "500")
        XCTAssertNil(events[0].metadata["Response"])
        XCTAssertEqual(events[0].message, DiagnosticRedactor.omittedBodyMessage)
        XCTAssertFalse(events[0].message.contains("legacy-access-token"))
        XCTAssertFalse(events[0].message.contains("legacy-refresh-token"))
        XCTAssertFalse(events[0].message.contains("profile"))
        XCTAssertFalse(events[0].message.contains("customer"))
        XCTAssertFalse(events[0].projectedDebugLogEntry.copyableText.contains("jane@example.com"))
        XCTAssertFalse(events[0].projectedDebugLogEntry.copyableText.contains("title-token"))
        XCTAssertFalse(events[0].projectedDebugLogEntry.copyableText.contains("eyJhbGci"))
        XCTAssertFalse(events[0].projectedDebugLogEntry.copyableText.contains("token=abc"))
        XCTAssertNil(defaults.data(forKey: DefaultsKey.debugLogEntries.rawValue))

        defaults.set(Data("not-json".utf8), forKey: DefaultsKey.debugLogEntries.rawValue)
        try await store.migrateLegacyIfNeeded()
        let snapshotAfterSecondMigrationAttempt = try await store.snapshot(.unscopedForMigrationOnly)
        XCTAssertEqual(snapshotAfterSecondMigrationAttempt.count, 1)
        XCTAssertNotNil(defaults.data(forKey: DefaultsKey.debugLogEntries.rawValue))
    }

    func testMigrateLegacyNonAPIBodyLikeEntriesUseOmittedMessageAcrossCategories() async throws {
        let legacy = [
            DebugLogEntry(
                type: .general,
                title: "General copied payload",
                details: """
                {
                  "customer": {"name": "Jane Athlete"},
                  "profile": {"email": "jane@example.com"},
                  "health": {"hrv": 42},
                  "location": {"lat": 37.7, "lng": -122.4}
                }
                """,
                metadata: ["Context": "debug import"]
            ),
            DebugLogEntry(
                type: .networkError,
                title: "Network copied response",
                details: "Raw response body contained customer profile and health location payload",
                metadata: [
                    "Context": "sync",
                    "response_body": #"{"customer":"Jane Athlete","profile":"raw"}"#
                ]
            )
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(legacy), forKey: DefaultsKey.debugLogEntries.rawValue)

        let store = makeStore()
        try await store.migrateLegacyIfNeeded()

        let events = try await store.snapshot(.unscopedForMigrationOnly)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.message)), [DiagnosticRedactor.omittedBodyMessage])
        for event in events {
            XCTAssertFalse(event.projectedDebugLogEntry.copyableText.contains("Jane Athlete"))
            XCTAssertFalse(event.projectedDebugLogEntry.copyableText.contains("jane@example.com"))
            XCTAssertFalse(event.projectedDebugLogEntry.copyableText.contains("\"health\""))
            XCTAssertFalse(event.projectedDebugLogEntry.copyableText.contains("\"location\""))
            XCTAssertNil(event.metadata["response_body"])
        }
    }

    func testSnapshotAppliesAndPersistsAgeRetentionWithoutNewWrite() async throws {
        let store = makeStore()
        try await store.append(event("before-window", at: now.addingTimeInterval(-60)))
        try await store.append(event("latest-before-idle", at: now))

        now = now.addingTimeInterval(8 * 24 * 60 * 60)

        let names = try await store.snapshot(.unscopedForMigrationOnly).map(\.name)
        XCTAssertEqual(names, [])
        let rawFile = try String(contentsOf: store.eventsFileURL)
        XCTAssertFalse(rawFile.contains("before-window"))
        XCTAssertFalse(rawFile.contains("latest-before-idle"))
    }

    func testSnapshotEvictsOversizedPreexistingStorageWithoutNewWrite() async throws {
        let initialStore = makeStore(maxBytes: 20_000)
        try await initialStore.append(event("oversized-1", at: now.addingTimeInterval(1), message: String(repeating: "a", count: 600)))
        try await initialStore.append(event("oversized-2", at: now.addingTimeInterval(2), message: String(repeating: "b", count: 600)))
        try await initialStore.append(event("oversized-3", at: now.addingTimeInterval(3), message: String(repeating: "c", count: 600)))

        let enforcingStore = makeStore(maxBytes: 1_200)
        let names = try await enforcingStore.snapshot(.unscopedForMigrationOnly).map(\.name)

        XCTAssertEqual(names, ["oversized-3"])
        let bytes = try Data(contentsOf: enforcingStore.eventsFileURL).count
        XCTAssertLessThanOrEqual(bytes, 1_200)
    }

    func testCorruptPersistedRecordsDoNotBlockSnapshotsAndAreDiscardedOnNextWrite() async throws {
        let store = makeStore()
        try await store.append(event("valid-before-corruption", at: now))
        try Data("{not-json}\n".utf8).append(to: store.eventsFileURL)

        let loaded = try await store.snapshot(.unscopedForMigrationOnly)
        XCTAssertEqual(loaded.map(\.name), ["valid-before-corruption"])

        try await store.append(event("valid-after-corruption", at: now.addingTimeInterval(1)))

        let rawFile = try String(contentsOf: store.eventsFileURL)
        let snapshotAfterRepair = try await store.snapshot(.unscopedForMigrationOnly)
        XCTAssertFalse(rawFile.contains("{not-json}"))
        XCTAssertEqual(snapshotAfterRepair.map(\.name), ["valid-after-corruption", "valid-before-corruption"])
    }

    func testRetentionEvictsEventsOlderThanSevenDaysAndOldestEventsOverSizeBudget() async throws {
        let store = makeStore(maxBytes: 1_200)
        try await store.append(event("too-old", at: now.addingTimeInterval(-8 * 24 * 60 * 60)))
        try await store.append(event("newer-1", at: now.addingTimeInterval(-30), message: String(repeating: "a", count: 260)))
        try await store.append(event("newer-2", at: now.addingTimeInterval(-20), message: String(repeating: "b", count: 260)))
        try await store.append(event("newer-3", at: now.addingTimeInterval(-10), message: String(repeating: "c", count: 260)))

        let names = try await store.snapshot(.unscopedForMigrationOnly).map(\.name)
        XCTAssertFalse(names.contains("too-old"))
        XCTAssertFalse(names.contains("newer-1"))
        XCTAssertEqual(names, ["newer-3", "newer-2"])
        let bytes = try Data(contentsOf: store.eventsFileURL).count
        XCTAssertLessThanOrEqual(bytes, 1_200)
    }

    func testConcurrentWritesAreSerializedAndSnapshotsAreImmutableNewestFirst() async throws {
        let store = makeStore()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    try await store.append(self.event("event-\(index)", at: self.now.addingTimeInterval(TimeInterval(index))))
                }
            }
            try await group.waitForAll()
        }

        let snapshot = try await store.snapshot(.unscopedForMigrationOnly)
        XCTAssertEqual(snapshot.count, 50)
        XCTAssertEqual(snapshot.first?.name, "event-49")

        try await store.append(event("event-50", at: now.addingTimeInterval(50)))
        XCTAssertEqual(snapshot.count, 50)
        let updatedSnapshot = try await store.snapshot(.unscopedForMigrationOnly)
        XCTAssertEqual(updatedSnapshot.first?.name, "event-50")
    }

    func testWritesUseCompleteUntilFirstUserAuthenticationFileProtection() async throws {
        let store = makeStore()
        try await store.append(event("protected", at: now))

        let protection = try await store.persistedFileProtection()
        XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
    }

    func testAccountSeparationStoresOnlyOneWayHashesAndAllowsSameCorrelationAcrossAccounts() async throws {
        let redactor = DiagnosticRedactor()
        let store = makeStore()
        try await store.append(redactor.redact(
            category: .sync,
            severity: .warning,
            name: "sync.retry.failed",
            message: "Retry failed",
            metadata: ["Context": "sync queue"],
            requestID: "req-shared",
            accountIdentifier: "user-a",
            timestamp: now
        ))
        try await store.append(redactor.redact(
            category: .sync,
            severity: .warning,
            name: "sync.retry.failed",
            message: "Retry failed",
            metadata: ["Context": "sync queue"],
            requestID: "req-shared",
            accountIdentifier: "user-b",
            timestamp: now.addingTimeInterval(1)
        ))

        let hashes = try await store.snapshot(.unscopedForMigrationOnly).compactMap(\.accountHash)
        XCTAssertEqual(Set(hashes).count, 2)
        XCTAssertFalse(hashes.contains("user-a"))
        XCTAssertFalse(hashes.contains("user-b"))
        let requestIDs = try await store.snapshot(.unscopedForMigrationOnly).map(\.requestID)
        XCTAssertEqual(requestIDs, ["req-shared", "req-shared"])
    }
}
