//
//  GarminCIQPairingStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2342: CIQ Devices pairing (not GCM) gates Start → Garmin.
//

import XCTest
@testable import AmakaFlowCompanion

final class GarminCIQPairingStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: GarminCIQPairingStore!

    @MainActor
    override func setUp() {
        super.setUp()
        suiteName = "GarminCIQPairingStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults, "UserDefaults suite must be available")
        defaults.removeObject(forKey: "garmin_ciq_devices_paired")
        store = GarminCIQPairingStore(defaults: defaults)
    }

    @MainActor
    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func testIsGarminWearableMatchesBFFFallbackName() {
        let device = Components.Schemas.PairedDevice(
            id: "tok-1",
            lastSyncAt: nil,
            model: nil,
            name: "Garmin",
            roles: nil
        )
        XCTAssertTrue(GarminCIQPairingStore.isGarminWearable(device))
    }

    @MainActor
    func testIsGarminWearableMatchesForerunner() {
        let device = Components.Schemas.PairedDevice(
            id: "tok-2",
            lastSyncAt: nil,
            model: "Forerunner 965",
            name: "Dave's watch",
            roles: nil
        )
        XCTAssertTrue(GarminCIQPairingStore.isGarminWearable(device))
    }

    @MainActor
    func testUpdateSetsHasPairedGarmin() {
        XCTAssertFalse(store.hasPairedGarmin)

        store.update(from: [
            Components.Schemas.PairedDevice(
                id: "tok",
                lastSyncAt: nil,
                model: nil,
                name: "Garmin",
                roles: nil
            )
        ])
        XCTAssertTrue(store.hasPairedGarmin)
        XCTAssertTrue(defaults.bool(forKey: "garmin_ciq_devices_paired"))

        store.update(from: [])
        XCTAssertFalse(store.hasPairedGarmin)
        XCTAssertFalse(defaults.bool(forKey: "garmin_ciq_devices_paired"))
    }
}
