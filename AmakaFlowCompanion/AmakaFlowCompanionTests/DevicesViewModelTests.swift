//
//  DevicesViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1996: Devices screen L1/L2/L3 coverage.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class DevicesViewModelTests: XCTestCase {
    private var api: MockAPIService!
    private var viewModel: DevicesViewModel!
    private let fixedNow = Date(timeIntervalSince1970: 1_779_977_300) // 2026-05-28T14:08:20Z

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
        viewModel = DevicesViewModel(apiService: api, now: { self.fixedNow })
    }

    override func tearDown() async throws {
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testLoad_successMapsPairedDevicesToContent() async {
        let devices = [
            device(id: "garmin-1", name: "Garmin Forerunner", model: "Forerunner 955", roles: [.workouts, .recovery]),
            device(id: "apple-1", name: "Apple Watch", model: "Series 9", roles: [.recovery])
        ]
        api.listDevicesResult = .success(devices)

        await viewModel.load()

        XCTAssertTrue(api.listDevicesCalled)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.devices, devices)
        XCTAssertEqual(viewModel.connectedSubtitle, "2 connected")
        XCTAssertNil(viewModel.ctaError)
    }

    func testLoad_emptyShowsHonestEmptyState() async {
        api.listDevicesResult = .success([])

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.connectedSubtitle, "0 connected")
    }

    func testLoad_errorMatrixMapsToCTAErrorAndRetry() async {
        let cases: [(Error, (CTAError) -> Bool, String)] = [
            (URLError(.notConnectedToInternet), { if case .network(let code, _) = $0 { return code == .notConnectedToInternet }; return false }, "network"),
            (APIError.serverError(503), { if case .http(let status, _, _) = $0 { return status == 503 }; return false }, "http"),
            (APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad shape"))), { if case .decoding = $0 { return true }; return false }, "decoding")
        ]

        for (error, matcher, label) in cases {
            api = MockAPIService()
            api.listDevicesResult = .failure(error)
            viewModel = DevicesViewModel(apiService: api, now: { self.fixedNow })

            await viewModel.load()

            guard case .error(let ctaError) = viewModel.state else {
                XCTFail("Expected error state for \(label), got \(viewModel.state)")
                continue
            }
            XCTAssertTrue(matcher(ctaError), "Wrong CTAError mapping for \(label): \(ctaError)")
            XCTAssertEqual(viewModel.ctaError, ctaError)
            XCTAssertEqual(viewModel.lastFailedAction, .load)

            api.listDevicesResult = .success([device(id: "retry-ok")])
            await viewModel.retryLastAction()
            XCTAssertEqual(viewModel.state, .content)
            XCTAssertNil(viewModel.ctaError)
        }
    }

    func testDismissLoadErrorKeepsErrorStateInsteadOfFakeEmptyList() async {
        api.listDevicesResult = .failure(URLError(.notConnectedToInternet))

        await viewModel.load()
        viewModel.dismissError()

        XCTAssertNil(viewModel.ctaError)
        guard case .error = viewModel.state else {
            return XCTFail("Dismissed load error must remain in error state, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.devices.isEmpty)
    }

    func testDisplayDevicesRenderModelSyncCaptionSymbolsAndRoleState() async {
        api.listDevicesResult = .success([
            device(
                id: "garmin-1",
                name: "Garmin Forerunner",
                model: "Forerunner 955",
                roles: [.workouts, .recovery],
                lastSyncAt: "2026-05-28T14:06:20Z"
            ),
            device(id: "whoop-1", name: "WHOOP Band", model: nil, roles: nil, lastSyncAt: nil)
        ])

        await viewModel.load()

        let displays = viewModel.displayDevices
        XCTAssertEqual(displays.count, 2)
        XCTAssertEqual(displays[0].modelSyncCaption, "FORERUNNER 955 · SYNCED 2M AGO")
        XCTAssertEqual(displays[0].syncCaption, "2m ago")
        XCTAssertEqual(displays[0].symbolName, "watchface.applewatch.case")
        XCTAssertTrue(viewModel.hasRole(.workouts, in: displays[0].device))
        XCTAssertTrue(viewModel.hasRole(.recovery, in: displays[0].device))
        XCTAssertFalse(viewModel.hasRole(.strength, in: displays[0].device))

        XCTAssertEqual(displays[1].modelSyncCaption, "SYNCED —")
        XCTAssertEqual(displays[1].symbolName, "heart.fill")
        XCTAssertFalse(viewModel.hasRole(.recovery, in: displays[1].device))
    }

    func testRelativeTimeAndRoleChipDisplayLogic() {
        XCTAssertEqual(DevicesViewModel.relativeSyncText(lastSyncAt: "2026-05-28T14:08:00Z", now: fixedNow), "now")
        XCTAssertEqual(DevicesViewModel.relativeSyncText(lastSyncAt: "2026-05-28T14:06:20Z", now: fixedNow), "2m ago")
        XCTAssertEqual(DevicesViewModel.relativeSyncText(lastSyncAt: "2026-05-28T12:08:20Z", now: fixedNow), "2h ago")
        XCTAssertEqual(DevicesViewModel.relativeSyncText(lastSyncAt: "2026-05-26T14:08:20Z", now: fixedNow), "2d ago")
        XCTAssertEqual(DevicesViewModel.relativeSyncText(lastSyncAt: nil, now: fixedNow), "—")
        XCTAssertEqual(DevicesViewModel.modelSyncCaption(model: nil, relativeSyncText: "2m ago"), "SYNCED 2M AGO")
        XCTAssertEqual(DevicesViewModel.displayRoles, [.workouts, .recovery, .strength])
        XCTAssertEqual(DevicesViewModel.roleLabel(.workouts), "Workouts")
        XCTAssertEqual(DevicesViewModel.roleLabel(.recovery), "Recovery")
        XCTAssertEqual(DevicesViewModel.roleLabel(.strength), "Strength")
    }

    func testPairSuccessReloadsDevicesAndClearsError() async {
        let paired = device(id: "garmin-new", name: "Garmin Fenix", model: "Fenix 8", roles: [.workouts])
        api.listDevicesResult = .success([paired])

        await viewModel.pair(shortCode: " ab12cd ")

        XCTAssertTrue(api.pairDeviceCalled)
        XCTAssertEqual(api.lastPairedShortCode, "AB12CD")
        XCTAssertTrue(api.listDevicesCalled)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.devices, [paired])
        XCTAssertNil(viewModel.ctaError)
        XCTAssertNil(viewModel.lastFailedAction)
    }

    func testPairFailureMapsServerDetailAndPreservesList() async {
        let existing = device(id: "garmin-existing", name: "Garmin Forerunner", roles: [.workouts])
        api.listDevicesResult = .success([existing])
        await viewModel.load()

        api.pairDeviceResult = .failure(APIError.serverErrorWithBody(410, "{\"detail\":\"Pairing code expired\"}"))

        await viewModel.pair(shortCode: "123456")

        XCTAssertTrue(api.pairDeviceCalled)
        XCTAssertEqual(viewModel.devices, [existing])
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.lastFailedAction, .pair)
        guard let ctaError = viewModel.ctaError else {
            return XCTFail("Expected CTAError for expired pair code")
        }
        XCTAssertEqual(ctaError, .http(status: 410, body: "{\"detail\":\"Pairing code expired\"}", requestId: nil))
        XCTAssertTrue(ctaError.userMessage.contains("Pairing code expired"))
    }

    func testPairLyingSuccessMapsServerMessageAndPreservesList() async {
        let existing = device(id: "garmin-existing", name: "Garmin Forerunner", roles: [.workouts])
        api.listDevicesResult = .success([existing])
        await viewModel.load()

        api.pairDeviceResult = .success(Components.Schemas.PairDeviceResult(message: "Pairing code expired", success: false))

        await viewModel.pair(shortCode: "123456")

        XCTAssertTrue(api.pairDeviceCalled)
        XCTAssertEqual(viewModel.devices, [existing])
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.lastFailedAction, .pair)
        guard let ctaError = viewModel.ctaError else {
            return XCTFail("Expected CTAError for success:false pair result")
        }
        guard case .lyingSuccess(let message, _, _) = ctaError else {
            return XCTFail("Expected lyingSuccess, got \(ctaError)")
        }
        XCTAssertEqual(message, "Pairing code expired")
    }

    func testRemoveSuccessReloadsDevicesWithoutRemovedDevice() async {
        let removed = device(id: "garmin-remove", name: "Garmin Forerunner", roles: [.workouts])
        api.listDevicesResult = .success([removed])
        await viewModel.load()

        api.listDevicesResult = .success([])
        await viewModel.remove(removed)

        XCTAssertTrue(api.revokeDeviceCalled)
        XCTAssertEqual(api.lastRevokedDeviceId, "garmin-remove")
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertNil(viewModel.ctaError)
        XCTAssertNil(viewModel.lastFailedAction)
    }

    func testRemoveFailureMapsErrorAndPreservesList() async {
        let existing = device(id: "garmin-existing", name: "Garmin Forerunner", roles: [.workouts])
        api.listDevicesResult = .success([existing])
        await viewModel.load()

        api.revokeDeviceResult = .failure(APIError.serverErrorWithBody(404, "{\"detail\":\"Device pairing not found\"}"))

        await viewModel.remove(existing)

        XCTAssertTrue(api.revokeDeviceCalled)
        XCTAssertEqual(api.lastRevokedDeviceId, "garmin-existing")
        XCTAssertEqual(viewModel.devices, [existing])
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.lastFailedAction, .remove(id: "garmin-existing"))
        guard let ctaError = viewModel.ctaError else {
            return XCTFail("Expected CTAError for failed revoke")
        }
        XCTAssertEqual(ctaError, .http(status: 404, body: "{\"detail\":\"Device pairing not found\"}", requestId: nil))
        XCTAssertTrue(ctaError.userMessage.contains("Device pairing not found"))
    }

    func testRemoveLyingSuccessMapsServerMessageAndPreservesList() async {
        let existing = device(id: "garmin-existing", name: "Garmin Forerunner", roles: [.workouts])
        api.listDevicesResult = .success([existing])
        await viewModel.load()

        api.revokeDeviceResult = .success(Components.Schemas.PairDeviceResult(message: "Remove failed", success: false))

        await viewModel.remove(existing)

        XCTAssertTrue(api.revokeDeviceCalled)
        XCTAssertEqual(viewModel.devices, [existing])
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.lastFailedAction, .remove(id: "garmin-existing"))
        guard let ctaError = viewModel.ctaError else {
            return XCTFail("Expected CTAError for success:false remove result")
        }
        guard case .lyingSuccess(let message, _, _) = ctaError else {
            return XCTFail("Expected lyingSuccess, got \(ctaError)")
        }
        XCTAssertEqual(message, "Remove failed")
    }

    func testGeneratedDecoderHandlesPairedDeviceList() throws {
        let json = """
        {
          "devices": [
            {
              "id": "garmin-1",
              "lastSyncAt": "2026-05-28T14:06:20Z",
              "model": "Forerunner 955",
              "name": "Garmin Forerunner",
              "roles": ["workouts", "recovery"]
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try APIService.makeGeneratedDecoder().decode(Components.Schemas.PairedDeviceList.self, from: json)

        XCTAssertEqual(decoded.devices?.first?.id, "garmin-1")
        XCTAssertEqual(decoded.devices?.first?.roles, [.workouts, .recovery])
    }

    func testFixtureServiceListDevicesReturnsRenderableDevices() async throws {
        let fixture = FixtureAPIService()

        let devices = try await fixture.listDevices()

        XCTAssertGreaterThanOrEqual(devices.count, 2)
        XCTAssertTrue(devices.contains { $0.name.contains("Garmin") && $0.roles?.contains(.workouts) == true })
        XCTAssertTrue(devices.contains { $0.name.contains("Apple Watch") && $0.roles?.contains(.recovery) == true })
    }

    private func device(
        id: String,
        name: String = "Device",
        model: String? = "Model",
        roles: [Components.Schemas.DeviceRole]? = nil,
        lastSyncAt: String? = "2026-05-28T14:07:00Z"
    ) -> Components.Schemas.PairedDevice {
        Components.Schemas.PairedDevice(
            id: id,
            lastSyncAt: lastSyncAt,
            model: model,
            name: name,
            roles: roles
        )
    }
}
