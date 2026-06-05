//
//  CoachAPIRepository.swift
//  AmakaFlow
//
//  AMA-1828: coach + planning + actions endpoints split out of
//  APIService.swift. Implemented as `extension APIService` so call sites
//  (WatchConnectivityManager, etc.) and APIServiceProviding conformance
//  keep working. Pure refactor.
//
//  AMA-1933 pilot: every endpoint in this repository routes through
//  APIService.request(...), the shared async request path that provides
//  typed APIError mapping plus structured start/end/fail observability.
//  Migrate other repositories by building URLRequest values and calling
//  request(_:decode:), requestData(_:), or requestVoid(_:) instead of
//  session.data(for:) directly.
//
//  Endpoints in this file:
//    GET  /v1/devices                           (listDevices)
//    POST /v1/devices/pair                      (pairDevice)
//    DELETE /v1/devices/{device_id}             (revokeDevice)
//    PUT  /v1/devices/{device_id}/roles         (setDeviceRoles)
//    GET  /v1/devices/watch-delivery/{workout_id}          (watchDeliveryStatus)
//    POST /v1/devices/watch-delivery/{workout_id}/resend   (resendWatchDelivery)
//    GET  /v1/library/items                    (listLibraryItems)
//    GET  /v1/library/items/{item_id}          (getLibraryItem)
//    GET  /v1/messaging/channels                (listMessagingChannels)
//    PUT  /v1/messaging/channels/{id}/prefs     (setChannelPrefs)
//    GET  /v1/coaching/profile                  (getCoachingProfile)
//    PUT  /v1/coaching/profile                  (upsertCoachingProfile)
//    PUT  /v1/readiness/sample                  (postReadinessSample)
//    GET  /v1/planning/days                     (fetchDayState/fetchDayStates)
//    STUB /coach/quick                          (askCoach; no backend route)
//    POST /api/v1/planning/resolve-conflict     (resolveConflict; deferred)
//    POST /v1/planning/generate-week            (generateWeek)
//    GET  /v1/planning/conflicts                (detectConflicts)
//    POST /v1/ingest/parse-text                 (parseWorkoutText)
//    GET  /v1/agent/actions                    (fetchAgentActions)
//    POST /v1/agent/actions/{id}/respond       (respondToAction)
//    POST /v1/agent/actions/{id}/undo          (undoAction)
//    STUB /analytics/shoes                      (fetchShoeComparison; no backend route)
//    GET  /v1/billing/subscription              (fetchSubscription)
//    STUB /preferences/notifications            (fetch/updateNotificationPreferences; no backend route)
//    GET  /progression/volume                   (fetchVolumeAnalytics)
//

import Foundation

extension APIService {

    // MARK: - Devices (AMA-1996)

    func listDevices() async throws -> [Components.Schemas.PairedDevice] {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/devices",
            method: "GET"
        )
        let response = try await self.request(
            request,
            decode: Components.Schemas.PairedDeviceList.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
        guard let devices = response.devices else {
            throw APIError.decodingError(
                DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Missing devices in PairedDeviceList")
                )
            )
        }
        return devices
    }

    func pairDevice(shortCode: String) async throws -> Components.Schemas.PairDeviceResult {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/devices/pair",
            method: "POST",
            body: try encodeJSONBody(["shortCode": shortCode])
        )
        return try await self.request(
            request,
            decode: Components.Schemas.PairDeviceResult.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func revokeDevice(id: String) async throws -> Components.Schemas.PairDeviceResult {
        let encodedID = try Self.deviceIDPathSegment(id)
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/devices/\(encodedID)",
            method: "DELETE"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.PairDeviceResult.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func setDeviceRoles(
        id: String,
        roles: [Components.Schemas.DeviceRole]
    ) async throws -> Components.Schemas.DeviceRolesResult {
        let encodedID = try Self.deviceIDPathSegment(id)
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/devices/\(encodedID)/roles",
            method: "PUT",
            body: try encodeJSONBody(["roles": roles.map(\.rawValue)])
        )
        return try await self.request(
            request,
            decode: Components.Schemas.DeviceRolesResult.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func watchDeliveryStatus(workoutId: String) async throws -> Components.Schemas.WatchDeliveryStatus {
        let encodedWorkoutID = try Self.pathSegment(workoutId)
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/devices/watch-delivery/\(encodedWorkoutID)",
            method: "GET"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.WatchDeliveryStatus.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func resendWatchDelivery(workoutId: String) async throws -> Components.Schemas.WatchResendResult {
        let encodedWorkoutID = try Self.pathSegment(workoutId)
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/devices/watch-delivery/\(encodedWorkoutID)/resend",
            method: "POST"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.WatchResendResult.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    static func deviceIDPathSegment(_ id: String) throws -> String {
        try pathSegment(id)
    }

    // MARK: - Library (AMA-2004)

    func listLibraryItems(
        kind: Components.Schemas.LibraryKind?,
        tag: String?
    ) async throws -> Components.Schemas.LibraryItemList {
        var queryItems: [URLQueryItem] = []
        if let kind {
            queryItems.append(URLQueryItem(name: "kind", value: kind.rawValue))
        }
        if let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }

        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/library/items",
            queryItems: queryItems,
            method: "GET"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.LibraryItemList.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func getLibraryItem(id: String) async throws -> Components.Schemas.LibraryItemDetail {
        let encodedID = try Self.pathSegment(id)
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/library/items/\(encodedID)",
            method: "GET"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.LibraryItemDetail.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    // MARK: - Messaging Channels (AMA-2027)

    func listMessagingChannels() async throws -> Components.Schemas.MessagingChannelList {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/messaging/channels",
            method: "GET"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.MessagingChannelList.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func setChannelPrefs(
        channelId: String,
        prefs: Components.Schemas.ChannelPrefsRequest
    ) async throws -> Components.Schemas.ChannelPrefsResult {
        let encodedID = try Self.pathSegment(channelId)
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/messaging/channels/\(encodedID)/prefs",
            method: "PUT",
            body: try encodeJSONBody(prefs)
        )
        return try await self.request(
            request,
            decode: Components.Schemas.ChannelPrefsResult.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    static func pathSegment(_ id: String) throws -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed),
              !encoded.isEmpty else {
            throw APIError.invalidURL
        }
        return encoded
    }

    // MARK: - Coaching Profile (AMA-1995)

    func getCoachingProfile() async throws -> Components.Schemas.CoachingProfile? {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/coaching/profile",
            method: "GET"
        )
        return try await requestOptionalOnStatus(
            request,
            decode: Components.Schemas.CoachingProfile.self,
            decoder: APIService.makeGeneratedDecoder(),
            emptyStatusCodes: [404],
            successStatusCodes: 200...200
        )
    }

    func upsertCoachingProfile(_ profile: Components.Schemas.CoachingProfileUpsert) async throws -> Components.Schemas.CoachingProfile {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/coaching/profile",
            method: "PUT",
            body: try encodeJSONBody(profile)
        )
        return try await self.request(
            request,
            decode: Components.Schemas.CoachingProfile.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    // MARK: - Readiness Sample (AMA-2052)

    private struct ReadinessSampleWriteRequest: Encodable {
        let sampleDate: String?
        let hrv: Double?
        let restingHr: Int?
        let sleepHours: Double?
        let sleepQuality: String?
        let source: String

        enum CodingKeys: String, CodingKey {
            case sampleDate = "sample_date"
            case hrv
            case restingHr = "resting_hr"
            case sleepHours = "sleep_hours"
            case sleepQuality = "sleep_quality"
            case source
        }
    }

    func postReadinessSample(
        hrv: Double?,
        restingHr: Int?,
        sleepHours: Double?,
        sleepQuality: String?,
        sampleDate: String?
    ) async throws -> ReadinessSampleWriteResult {
        let body = ReadinessSampleWriteRequest(
            sampleDate: sampleDate,
            hrv: hrv,
            restingHr: restingHr,
            sleepHours: sleepHours,
            sleepQuality: sleepQuality,
            source: "apple_health"
        )
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/readiness/sample",
            method: "PUT",
            body: try encodeJSONBody(body)
        )
        return try await self.request(
            request,
            decode: ReadinessSampleWriteResult.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    // MARK: - Readiness (AMA-2054)

    private struct ReadinessSourcePrefWriteRequest: Encodable {
        let metric: String
        let source: String
        let deviceId: String?

        enum CodingKeys: String, CodingKey {
            case metric
            case source
            case deviceId = "device_id"
        }
    }

    func readinessToday() async throws -> Components.Schemas.ReadinessToday {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/readiness/today",
            method: "GET"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.ReadinessToday.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func readinessTrend(metric: String, days: Int) async throws -> Components.Schemas.ReadinessTrend {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/readiness/trend",
            queryItems: [
                URLQueryItem(name: "metric", value: metric),
                URLQueryItem(name: "days", value: String(days))
            ],
            method: "GET"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.ReadinessTrend.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func readinessSourcePrefs() async throws -> Components.Schemas.ReadinessSourcePrefs {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/readiness/source-prefs",
            method: "GET"
        )
        return try await self.request(
            request,
            decode: Components.Schemas.ReadinessSourcePrefs.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    func setReadinessSourcePref(metric: String, source: String, deviceId: String?) async throws -> Components.Schemas.ReadinessSourcePref {
        let body = ReadinessSourcePrefWriteRequest(metric: metric, source: source, deviceId: deviceId)
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/readiness/source-prefs",
            method: "PUT",
            body: try encodeJSONBody(body)
        )
        return try await self.request(
            request,
            decode: Components.Schemas.ReadinessSourcePref.self,
            decoder: APIService.makeGeneratedDecoder(),
            successStatusCodes: 200...200
        )
    }

    // MARK: - DayState / Coach / Conflict (AMA-1150)

    /// Stable yyyy-MM-dd formatter (DateFormatter init is expensive — build once).
    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Fetch today's DayState from the BFF range-based planning API.
    func fetchDayState() async throws -> DayState {
        let today = Self.dayKeyFormatter.string(from: Date())
        guard let state = try await fetchDayStates(from: today, to: today).first else {
            throw APIError.notFound
        }
        return state
    }

    /// Ask the AI coach a quick question
    func askCoach(question: String) async throws -> String {
        // NOT IMPLEMENTED (AMA-1932): no backend route
        throw APIError.notImplemented
    }

    /// Resolve a training conflict (adjust or keep)
    func resolveConflict(action: String, message: String) async throws {
        // TODO(AMA-1936/1937/1938): repoint to bffURL once the BFF wedge ships
        let request = try await makeAPIRequest(
            path: "/api/v1/planning/resolve-conflict",
            method: "POST",
            body: try encodeJSONBody(["action": action, "message": message])
        )
        try await requestVoid(request)
    }

    // MARK: - Planning API (AMA-1147 / AMA-1133)

    func fetchDayStates(from: String, to: String) async throws -> [DayState] {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/planning/days",
            queryItems: [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to)
            ],
            method: "GET"
        )
        return try await self.request(request, decode: [DayState].self, successStatusCodes: 200...200)
    }

    func generateWeek(request genRequest: GenerateWeekRequest? = nil) async throws -> ProposedPlan {
        let body = try encodeJSONBody(genRequest ?? GenerateWeekRequest(startDate: nil, preferences: nil))
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/planning/generate-week",
            method: "POST",
            body: body
        )
        return try await self.request(request, decode: ProposedPlan.self, successStatusCodes: 200...200)
    }

    func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict] {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/planning/conflicts",
            queryItems: [
                URLQueryItem(name: "from", value: startDate),
                URLQueryItem(name: "to", value: endDate)
            ],
            method: "GET"
        )
        return try await self.request(request, decode: [Conflict].self, successStatusCodes: 200...200)
    }

    func parseWorkoutText(text: String, context: String? = nil) async throws -> ParseTextResult {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/ingest/parse-text",
            method: "POST",
            body: try encodeJSONBody(ParseTextRequest(text: text, source: context))
        )
        return try await self.request(request, decode: ParseTextResult.self, successStatusCodes: 200...200)
    }

    // MARK: - Agent Actions API (AMA-1956 / AMA-1934)

    func fetchAgentActions(status: String? = nil) async throws -> [AgentAction] {
        let queryItems = status.map { [URLQueryItem(name: "status", value: $0)] } ?? []
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/agent/actions",
            queryItems: queryItems,
            method: "GET"
        )
        return try await self.request(request, decode: [AgentAction].self, successStatusCodes: 200...200)
    }

    func respondToAction(id: String, decision: String) async throws -> AgentAction {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/agent/actions/\(id)/respond",
            method: "POST",
            body: try encodeJSONBody(["decision": decision])
        )
        return try await self.request(request, decode: AgentAction.self, successStatusCodes: 200...200)
    }

    func undoAction(id: String) async throws -> AgentAction {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/agent/actions/\(id)/undo",
            method: "POST"
        )
        return try await self.request(request, decode: AgentAction.self, successStatusCodes: 200...200)
    }

    // MARK: - Analytics API (AMA-1147 / AMA-1133)

    func fetchShoeComparison() async throws -> [ShoeStats] {
        // NOT IMPLEMENTED (AMA-1932): no backend route
        throw APIError.notImplemented
    }

    // MARK: - Billing API (AMA-1147 / AMA-1133)

    func fetchSubscription() async throws -> Subscription {
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/billing/subscription",
            method: "GET"
        )
        return try await self.request(
            request,
            decode: Subscription.self,
            successStatusCodes: 200...200
        )
    }

    // MARK: - Notification Preferences API (AMA-1147 / AMA-1133)

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        // NOT IMPLEMENTED (AMA-1932): no backend route
        throw APIError.notImplemented
    }

    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences {
        // NOT IMPLEMENTED (AMA-1932): no backend route
        throw APIError.notImplemented
    }

    // MARK: - Volume Analytics (AMA-1414)

    func fetchVolumeAnalytics(startDate: String, endDate: String, granularity: String) async throws -> VolumeAnalyticsResponse {
        let request = try await makeAPIRequest(
            path: "/progression/volume",
            queryItems: [
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate),
                URLQueryItem(name: "granularity", value: granularity)
            ],
            method: "GET"
        )
        return try await self.request(request, decode: VolumeAnalyticsResponse.self, successStatusCodes: 200...200)
    }
}
