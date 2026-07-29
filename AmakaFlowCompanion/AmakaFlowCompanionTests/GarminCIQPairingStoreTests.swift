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
        let defaults = UserDefaults(suiteName: "GarminCIQPairingStoreTests.\(UUID().uuidString)")!
        let store = GarminCIQPairingStore(defaults: defaults)
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

        store.update(from: [])
        XCTAssertFalse(store.hasPairedGarmin)
    }
}
