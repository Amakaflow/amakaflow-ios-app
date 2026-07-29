// GarminCIQAppIdentityTests.swift
// AMA-2342 — keep Companion CIQ UUID aligned with the sideloaded widget.

import XCTest
@testable import AmakaFlowCompanion

final class GarminCIQAppIdentityTests: XCTestCase {
    func testCIQAppUUIDMatchesSideloadedWidgetManifest() {
        // amakaflow-garmin-ciq/manifest.xml application id=
        let expected = UUID(uuidString: "d79bef4b-8805-44f2-8cdb-9b784a3be996")
        XCTAssertEqual(GarminCIQAppIdentity.appUUID, expected)
        XCTAssertEqual(GarminCIQAppIdentity.storeUUID, expected)

        let status = GarminConnectManager.shared.getDetailedStatus()
        let reported = status["appUUID"] as? String
        XCTAssertEqual(
            reported?.lowercased(),
            expected?.uuidString.lowercased(),
            "GarminConnectManager must expose the same CIQ app UUID used for openApp"
        )
    }
}
