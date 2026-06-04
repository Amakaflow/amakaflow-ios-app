//
//  InstagramImportModeTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for InstagramImportMode enum and IngestTextResponse decoding
//

import XCTest
@testable import AmakaFlowCompanion

final class InstagramImportModeTests: XCTestCase {

    // MARK: - InstagramImportMode Enum

    func testInstagramImportModeRawValues() {
        XCTAssertEqual(InstagramImportMode.automatic.rawValue, "automatic")
        XCTAssertEqual(InstagramImportMode.manual.rawValue, "manual")
    }

    func testInstagramImportModeInitFromRawValue() {
        // Ensures @AppStorage round-trip works
        XCTAssertEqual(InstagramImportMode(rawValue: "automatic"), .automatic)
        XCTAssertEqual(InstagramImportMode(rawValue: "manual"), .manual)
        XCTAssertNil(InstagramImportMode(rawValue: "unknown"))
    }

    func testInstagramImportModeTitles() {
        XCTAssertEqual(InstagramImportMode.automatic.title, "Automatic")
        XCTAssertEqual(InstagramImportMode.manual.title, "Manual")
    }

    func testInstagramImportModeSubtitles() {
        XCTAssertTrue(InstagramImportMode.automatic.subtitle.contains("Apify"))
        XCTAssertTrue(InstagramImportMode.manual.subtitle.contains("caption"))
    }

    func testInstagramImportModeAllCases() {
        XCTAssertEqual(InstagramImportMode.allCases.count, 2)
        XCTAssertTrue(InstagramImportMode.allCases.contains(.automatic))
        XCTAssertTrue(InstagramImportMode.allCases.contains(.manual))
    }

    // MARK: - IngestTextResponse Decoding

    func testIngestTextResponseDecodesFullPayload() throws {
        let json = """
        {"name": "AMRAP 10 min", "sport": "strength", "source": "instagram"}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(IngestTextResponse.self, from: json)

        XCTAssertEqual(response.name, "AMRAP 10 min")
        XCTAssertEqual(response.sport, "strength")
        XCTAssertEqual(response.source, "instagram")
    }

    func testIngestTextResponseDecodesPartialPayload() throws {
        let json = """
        {"name": null, "sport": null, "source": null}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(IngestTextResponse.self, from: json)

        XCTAssertNil(response.name)
        XCTAssertNil(response.sport)
        XCTAssertNil(response.source)
    }

    func testIngestTextResponseIgnoresExtraFields() throws {
        // Backend returns a full Workout JSON; our struct should decode fine
        let json = """
        {
            "name": "Full Body Workout",
            "sport": "strength",
            "source": "instagram",
            "id": "wk_12345",
            "duration": 3600,
            "intervals": [],
            "description": "A great workout"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(IngestTextResponse.self, from: json)

        XCTAssertEqual(response.name, "Full Body Workout")
        XCTAssertEqual(response.sport, "strength")
        XCTAssertEqual(response.source, "instagram")
    }

    func testIngestTextResponseDecodesEmptyObject() throws {
        let json = "{}".data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(IngestTextResponse.self, from: json)

        XCTAssertNil(response.name)
        XCTAssertNil(response.sport)
        XCTAssertNil(response.source)
    }
}

final class SettingsRefreshSectionModelTests: XCTestCase {
    func testV1SectionsExposeGroupedSettingsInOrder() {
        let sections = SettingsRefreshSectionModel.v1Sections(includeDebug: false)

        XCTAssertEqual(
            sections.map(\.id),
            ["connections", "profile_training", "coaching", "nutrition_activity", "app"]
        )
        XCTAssertEqual(sections.first?.rows.map(\.destination), [.connections])
        XCTAssertEqual(
            sections.first { $0.id == "profile_training" }?.rows.map(\.destination),
            [.editProfile, .trainingPreferences, .equipment]
        )
    }

    func testV1SectionsRemoveLegacyWebSyncRow() {
        let destinations = SettingsRefreshSectionModel
            .v1Sections(includeDebug: false)
            .flatMap(\.rows)
            .map(\.destination)

        XCTAssertFalse(destinations.contains(.syncDashboard))
        XCTAssertTrue(destinations.contains(.connections))
        XCTAssertTrue(destinations.contains(.readinessSources))
        XCTAssertTrue(destinations.contains(.accountPrivacyData))
    }

    func testDebugRowsAreDebugOnly() {
        let productionSections = SettingsRefreshSectionModel.v1Sections(includeDebug: false)
        let debugSections = SettingsRefreshSectionModel.v1Sections(includeDebug: true)
        let productionDestinations = productionSections.flatMap(\.rows).map(\.destination)
        let debugDestinations = debugSections.flatMap(\.rows).map(\.destination)

        XCTAssertFalse(productionSections.map(\.id).contains("debug"))
        XCTAssertTrue(debugSections.map(\.id).contains("debug"))
        XCTAssertFalse(productionDestinations.contains(.debugSettings))
        XCTAssertFalse(productionDestinations.contains(.errorLog))
        XCTAssertFalse(productionDestinations.contains(.workoutDebug))
        XCTAssertTrue(debugDestinations.contains(.debugSettings))
        XCTAssertTrue(debugDestinations.contains(.errorLog))
        XCTAssertTrue(debugDestinations.contains(.workoutDebug))
    }

    func testSettingsRowIDsAreUnique() {
        let rows = SettingsRefreshSectionModel.v1Sections(includeDebug: true).flatMap(\.rows)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }
}

final class ConnectionsHubViewModelTests: XCTestCase {
    func testConnectionsDeriveConnectedStatusesFromProvider() {
        let provider = FakeConnectionsHubStatusProvider(
            appleWatchReachable: true,
            appleWatchInstalled: true,
            devicePreference: .appleWatchPhone,
            garminConnected: true,
            garminDeviceName: "Forerunner 955",
            telegramLinked: true,
            telegramIdentifier: "12345",
            syncSummary: .healthy,
            connectedCalendars: [
                ConnectedCalendar(id: "cal-1", name: "Google", provider: "google", status: "active", email: "ada@example.com", lastSyncAt: nil)
            ]
        )

        let items = ConnectionsHubViewModel.makeItems(from: provider)
        let statuses = Dictionary(uniqueKeysWithValues: items.map { ($0.kind, $0.status) })

        XCTAssertEqual(statuses[.appleWatch], .connected)
        XCTAssertEqual(statuses[.garmin], .connected)
        XCTAssertEqual(statuses[.telegram], .connected)
        XCTAssertEqual(statuses[.sync], .healthy)
        XCTAssertEqual(statuses[.calendar], .connected)
        XCTAssertEqual(items.filter { $0.status.isOn }.count, 5)
        XCTAssertEqual(items.filter { !$0.status.isOn }.count, 0)
    }

    func testAppleWatchPreferenceAloneDoesNotCountAsConnected() {
        let provider = FakeConnectionsHubStatusProvider(
            appleWatchReachable: false,
            appleWatchInstalled: false,
            devicePreference: .appleWatchPhone,
            garminConnected: false,
            garminDeviceName: nil,
            telegramLinked: false,
            telegramIdentifier: nil,
            syncSummary: .healthy,
            connectedCalendars: []
        )

        let items = ConnectionsHubViewModel.makeItems(from: provider)
        let appleWatch = items.first { $0.kind == .appleWatch }

        XCTAssertEqual(appleWatch?.status, .off)
    }

    func testConnectionsDeriveOffStatusesFromProvider() {
        let provider = FakeConnectionsHubStatusProvider(
            appleWatchReachable: false,
            appleWatchInstalled: false,
            devicePreference: .phoneOnly,
            garminConnected: false,
            garminDeviceName: nil,
            telegramLinked: false,
            telegramIdentifier: nil,
            syncSummary: SyncQueueSummary(
                pendingCount: 0,
                inFlightCount: 0,
                failedCount: 1,
                poisonCount: 0,
                lastAttemptedAt: nil,
                latestError: "failed"
            ),
            connectedCalendars: [
                ConnectedCalendar(id: "cal-error", name: "Expired", provider: "google", status: "error", email: nil, lastSyncAt: nil)
            ]
        )

        let items = ConnectionsHubViewModel.makeItems(from: provider)
        let statuses = Dictionary(uniqueKeysWithValues: items.map { ($0.kind, $0.status) })

        XCTAssertEqual(statuses[.appleWatch], .off)
        XCTAssertEqual(statuses[.garmin], .off)
        XCTAssertEqual(statuses[.telegram], .off)
        XCTAssertEqual(statuses[.sync], .off)
        XCTAssertEqual(statuses[.calendar], .off)
        XCTAssertEqual(items.filter { $0.status.isOn }.count, 0)
        XCTAssertEqual(items.filter { !$0.status.isOn }.count, 5)
    }
}

private struct FakeConnectionsHubStatusProvider: ConnectionsHubStatusProviding {
    let appleWatchReachable: Bool
    let appleWatchInstalled: Bool
    let devicePreference: DevicePreference
    let garminConnected: Bool
    let garminDeviceName: String?
    let telegramLinked: Bool
    let telegramIdentifier: String?
    let syncSummary: SyncQueueSummary
    let connectedCalendars: [ConnectedCalendar]
}
