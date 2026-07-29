//
//  GarminCIQPairingStoreTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2342: CIQ Devices pairing (not GCM) gates Start → Garmin.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class GarminCIQPairingStoreTests: XCTestCase {
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

    func testUpdateSetsHasPairedGarmin() {
        let suite = "ciq.pairing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        // Ensure a clean key even if suite falls back to .standard
        defaults.removeObject(forKey: "garmin_ciq_devices_paired")

        let store = GarminCIQPairingStore(defaults: defaults)
        XCTAssertFalse(store.hasPairedGarmin, "fresh store should start unpaired")

        let garmin = Components.Schemas.PairedDevice(
            id: "tok",
            lastSyncAt: nil,
            model: nil,
            name: "Garmin",
            roles: nil
        )
        XCTAssertTrue(GarminCIQPairingStore.isGarminWearable(garmin))

        store.update(from: [garmin])
        XCTAssertTrue(store.hasPairedGarmin, "update with Garmin row should set paired")
        XCTAssertTrue(defaults.bool(forKey: "garmin_ciq_devices_paired"))

        store.update(from: [])
        XCTAssertFalse(store.hasPairedGarmin, "empty list should clear paired")
        XCTAssertFalse(defaults.bool(forKey: "garmin_ciq_devices_paired"))

        if defaults !== UserDefaults.standard {
            defaults.removePersistentDomain(forName: suite)
        } else {
            defaults.removeObject(forKey: "garmin_ciq_devices_paired")
        }
    }
}
