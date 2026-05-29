//
//  MessagingViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2027: Messaging channels + coaching-delivery prefs coverage.
//

import XCTest

@testable import AmakaFlowCompanion

@MainActor
final class MessagingViewModelTests: XCTestCase {
    private var api: MockAPIService!
    private var viewModel: MessagingViewModel!

    override func setUp() async throws {
        try await super.setUp()
        api = MockAPIService()
        viewModel = MessagingViewModel(apiService: api)
    }

    override func tearDown() async throws {
        viewModel = nil
        api = nil
        try await super.tearDown()
    }

    func testLoadSuccessSurfacesChannelsAndDeliveryLive() async {
        let response = Components.Schemas.MessagingChannelList(
            channels: [telegram(briefing: true), comingSoon(id: "whatsapp", name: "WhatsApp")],
            deliveryLive: false
        )
        api.listMessagingChannelsResult = .success(response)

        await viewModel.load()

        XCTAssertTrue(api.listMessagingChannelsCalled)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.channels, response.channels)
        XCTAssertFalse(viewModel.deliveryLive)
        XCTAssertEqual(viewModel.connectedSubtitle, "1 connected")
        XCTAssertNil(viewModel.ctaError)
    }

    func testLoadEmptyShowsHonestEmptyState() async {
        api.listMessagingChannelsResult = .success(Components.Schemas.MessagingChannelList(channels: [], deliveryLive: false))

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(viewModel.channels.isEmpty)
        XCTAssertFalse(viewModel.deliveryLive)
        XCTAssertEqual(viewModel.connectedSubtitle, "No channels")
    }

    func testLoadErrorMapsToCTAErrorAndRetry() async {
        api.listMessagingChannelsResult = .failure(APIError.serverErrorWithBody(503, "{\"detail\":\"Messaging unavailable\"}"))

        await viewModel.load()

        guard case .error(let ctaError) = viewModel.state else {
            return XCTFail("Expected error state, got \(viewModel.state)")
        }
        XCTAssertEqual(ctaError, .http(status: 503, body: "{\"detail\":\"Messaging unavailable\"}", requestId: nil))
        XCTAssertEqual(viewModel.ctaError, ctaError)
        XCTAssertEqual(viewModel.lastFailedAction, .load)

        api.listMessagingChannelsResult = .success(Components.Schemas.MessagingChannelList(channels: [telegram()], deliveryLive: false))
        await viewModel.retryLastAction()

        XCTAssertEqual(viewModel.state, .content)
        XCTAssertNil(viewModel.ctaError)
    }

    func testSetPrefsSuccessUpdatesOnlyTargetRow() async {
        let telegram = telegram(id: "telegram", briefing: true, checkin: true, swap: false)
        let slack = comingSoon(id: "slack", name: "Slack")
        api.listMessagingChannelsResult = .success(Components.Schemas.MessagingChannelList(channels: [telegram, slack], deliveryLive: false))
        await viewModel.load()

        api.setChannelPrefsResult = .success(
            Components.Schemas.ChannelPrefsResult(
                channelId: "telegram",
                prefs: Components.Schemas.ChannelPrefs(briefing: false, checkin: true, quietEnd: "07:00", quietStart: "22:00", swap: true),
                success: true
            )
        )

        await viewModel.setPrefs(telegram, prefs: Components.Schemas.ChannelPrefsRequest(briefing: false, checkin: true, quietEnd: "07:00", quietStart: "22:00", swap: true))

        XCTAssertTrue(api.setChannelPrefsCalled)
        XCTAssertEqual(api.lastSetChannelPrefsId, "telegram")
        XCTAssertEqual(api.lastSetChannelPrefs?.briefing, false)
        XCTAssertEqual(viewModel.channels.count, 2)
        XCTAssertEqual(viewModel.channels.first?.prefs?.briefing, false)
        XCTAssertEqual(viewModel.channels.first?.prefs?.swap, true)
        XCTAssertEqual(viewModel.channels.last, slack)
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertNil(viewModel.ctaError)
        XCTAssertNil(viewModel.lastFailedAction)
    }

    func testSetPrefsFailureMapsCTAErrorAndKeepsListIntact() async {
        let existing = telegram(id: "telegram", briefing: true, checkin: true, swap: false)
        api.listMessagingChannelsResult = .success(Components.Schemas.MessagingChannelList(channels: [existing], deliveryLive: false))
        await viewModel.load()

        let invalidRequest = Components.Schemas.ChannelPrefsRequest(briefing: false, checkin: true, quietEnd: "07:00", quietStart: "25:00", swap: false)
        api.setChannelPrefsResult = .failure(APIError.serverErrorWithBody(422, "{\"detail\":\"Invalid quietStart\"}"))

        await viewModel.setPrefs(existing, prefs: invalidRequest)

        XCTAssertTrue(api.setChannelPrefsCalled)
        XCTAssertEqual(api.lastSetChannelPrefsId, "telegram")
        XCTAssertEqual(viewModel.channels, [existing])
        XCTAssertEqual(viewModel.state, .content)
        XCTAssertEqual(viewModel.lastFailedAction, .setPrefs(channelId: "telegram", prefs: invalidRequest))
        guard let ctaError = viewModel.ctaError else {
            return XCTFail("Expected CTAError")
        }
        XCTAssertEqual(ctaError, .http(status: 422, body: "{\"detail\":\"Invalid quietStart\"}", requestId: nil))
        XCTAssertTrue(ctaError.userMessage.contains("Invalid quietStart"))
    }

    func testSetPrefsConcurrentDifferentChannelSuccessDoesNotClearOtherChannelFailure() async throws {
        let primary = telegram(id: "telegram", briefing: true, checkin: true, swap: false)
        let backup = telegram(id: "telegram-backup", briefing: false, checkin: true, swap: false)
        api.listMessagingChannelsResult = .success(Components.Schemas.MessagingChannelList(channels: [primary, backup], deliveryLive: false))
        await viewModel.load()

        let failingRequest = Components.Schemas.ChannelPrefsRequest(briefing: false, checkin: true, quietEnd: "07:00", quietStart: "25:00", swap: false)
        let succeedingRequest = Components.Schemas.ChannelPrefsRequest(briefing: true, checkin: false, quietEnd: "06:00", quietStart: "22:00", swap: true)
        api.setChannelPrefsResultsByChannel = [
            "telegram": .failure(APIError.serverErrorWithBody(422, "{\"detail\":\"Invalid quietStart\"}")),
            "telegram-backup": .success(
                Components.Schemas.ChannelPrefsResult(
                    channelId: "telegram-backup",
                    prefs: Components.Schemas.ChannelPrefs(briefing: true, checkin: false, quietEnd: "06:00", quietStart: "22:00", swap: true),
                    success: true
                )
            )
        ]
        api.setChannelPrefsDelaysByChannel = [
            "telegram": 20_000_000,
            "telegram-backup": 80_000_000
        ]

        async let failingUpdate: Void = viewModel.setPrefs(primary, prefs: failingRequest)
        async let succeedingUpdate: Void = viewModel.setPrefs(backup, prefs: succeedingRequest)
        _ = await (failingUpdate, succeedingUpdate)

        XCTAssertEqual(api.setChannelPrefsCallCount, 2)
        XCTAssertEqual(viewModel.lastFailedAction, .setPrefs(channelId: "telegram", prefs: failingRequest))
        XCTAssertEqual(viewModel.ctaError, .http(status: 422, body: "{\"detail\":\"Invalid quietStart\"}", requestId: nil))
        XCTAssertEqual(viewModel.channels.first(where: { $0.id == "telegram" })?.prefs?.quietStart, "21:00")
        XCTAssertEqual(viewModel.channels.first(where: { $0.id == "telegram-backup" })?.prefs?.swap, true)
    }

    func testSetPrefsInFlightGuardBlocksConcurrentSameChannelWrites() async throws {
        let existing = telegram(id: "telegram", briefing: true, checkin: true, swap: false)
        api.listMessagingChannelsResult = .success(Components.Schemas.MessagingChannelList(channels: [existing], deliveryLive: false))
        api.setChannelPrefsDelayNanoseconds = 150_000_000
        await viewModel.load()

        let firstRequest = Components.Schemas.ChannelPrefsRequest(briefing: false, checkin: true, quietEnd: "07:00", quietStart: "21:00", swap: false)
        let secondRequest = Components.Schemas.ChannelPrefsRequest(briefing: true, checkin: false, quietEnd: "07:00", quietStart: "21:00", swap: false)

        let first = Task { await viewModel.setPrefs(existing, prefs: firstRequest) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let second = Task { await viewModel.setPrefs(existing, prefs: secondRequest) }

        await second.value
        XCTAssertEqual(api.setChannelPrefsCallCount, 1)
        XCTAssertEqual(api.lastSetChannelPrefs?.briefing, false)
        XCTAssertTrue(viewModel.prefUpdatesInFlight.contains("telegram"))

        await first.value
        XCTAssertEqual(api.setChannelPrefsCallCount, 1)
        XCTAssertFalse(viewModel.prefUpdatesInFlight.contains("telegram"))
        XCTAssertNil(viewModel.ctaError)
    }

    func testGeneratedDecoderHandlesMessagingSchemas() throws {
        let listJSON = """
        {
          "channels": [
            {
              "id": "telegram",
              "name": "Telegram",
              "handle": "@amaka",
              "connected": true,
              "comingSoon": false,
              "prefs": {
                "briefing": true,
                "checkin": false,
                "swap": true,
                "quietStart": "21:00",
                "quietEnd": "07:00"
              }
            }
          ],
          "deliveryLive": false
        }
        """.data(using: .utf8)!

        let requestJSON = """
        { "briefing": false, "checkin": true, "swap": false, "quietStart": "22:00", "quietEnd": "06:00" }
        """.data(using: .utf8)!

        let resultJSON = """
        { "success": true, "channelId": "telegram", "prefs": { "briefing": false, "checkin": true, "swap": false } }
        """.data(using: .utf8)!

        let list = try APIService.makeGeneratedDecoder().decode(Components.Schemas.MessagingChannelList.self, from: listJSON)
        let request = try APIService.makeGeneratedDecoder().decode(Components.Schemas.ChannelPrefsRequest.self, from: requestJSON)
        let result = try APIService.makeGeneratedDecoder().decode(Components.Schemas.ChannelPrefsResult.self, from: resultJSON)

        XCTAssertEqual(list.channels?.first?.id, "telegram")
        XCTAssertEqual(list.channels?.first?.prefs?.quietStart, "21:00")
        XCTAssertEqual(list.deliveryLive, false)
        XCTAssertEqual(request.quietEnd, "06:00")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.channelId, "telegram")
        XCTAssertEqual(result.prefs?.briefing, false)
    }

    func testFixtureServiceSurfacesTelegramAndDeliveryNotLive() async throws {
        let fixture = FixtureAPIService()

        let response = try await fixture.listMessagingChannels()

        XCTAssertFalse(response.deliveryLive == true)
        XCTAssertTrue(response.channels?.contains { $0.id == "telegram" && $0.connected == true } == true)
        XCTAssertTrue(response.channels?.contains { $0.id == "whatsapp" && $0.comingSoon == true } == true)
        XCTAssertTrue(response.channels?.contains { $0.id == "slack" && $0.comingSoon == true } == true)
    }

    private func telegram(
        id: String = "telegram",
        briefing: Bool = true,
        checkin: Bool = true,
        swap: Bool = false
    ) -> Components.Schemas.MessagingChannel {
        Components.Schemas.MessagingChannel(
            comingSoon: false,
            connected: true,
            handle: "@amaka",
            id: id,
            name: "Telegram",
            prefs: Components.Schemas.ChannelPrefs(
                briefing: briefing,
                checkin: checkin,
                quietEnd: "07:00",
                quietStart: "21:00",
                swap: swap
            )
        )
    }

    private func comingSoon(id: String, name: String) -> Components.Schemas.MessagingChannel {
        Components.Schemas.MessagingChannel(
            comingSoon: true,
            connected: false,
            handle: nil,
            id: id,
            name: name,
            prefs: Components.Schemas.ChannelPrefs(briefing: false, checkin: false, swap: false)
        )
    }
}
