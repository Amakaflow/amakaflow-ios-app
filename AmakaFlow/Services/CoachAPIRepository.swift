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
//    GET  /v1/planning/days                     (fetchDayState/fetchDayStates)
//    STUB /coach/quick                          (askCoach; no backend route)
//    POST /api/v1/planning/resolve-conflict     (resolveConflict; deferred)
//    POST /api/v1/planning/generate-week        (generateWeek; deferred)
//    GET  /v1/planning/conflicts                (detectConflicts)
//    POST /api/v1/planning/parse-workout        (parseWorkoutText; deferred)
//    GET  /v1/agent/actions                    (fetchAgentActions)
//    POST /v1/agent/actions/{id}/respond       (respondToAction)
//    POST /v1/agent/actions/{id}/undo          (undoAction)
//    STUB /analytics/shoes                      (fetchShoeComparison; no backend route)
//    STUB /billing/subscription                 (fetchSubscription; no backend route)
//    STUB /preferences/notifications            (fetch/updateNotificationPreferences; no backend route)
//    GET  /progression/volume                   (fetchVolumeAnalytics)
//

import Foundation

extension APIService {

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
        // TODO(AMA-1936/1937/1938): repoint to bffURL once the BFF wedge ships
        let body = try encodeJSONBody(genRequest ?? GenerateWeekRequest(startDate: nil, preferences: nil))
        let request = try await makeAPIRequest(
            path: "/api/v1/planning/generate-week",
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

    func parseWorkoutText(text: String, context: String? = nil) async throws -> ParsedWorkout {
        // TODO(AMA-1936/1937/1938): repoint to bffURL once the BFF wedge ships
        let request = try await makeAPIRequest(
            path: "/api/v1/planning/parse-workout",
            method: "POST",
            body: try encodeJSONBody(ParseWorkoutRequest(text: text, context: context))
        )
        return try await self.request(request, decode: ParsedWorkout.self, successStatusCodes: 200...200)
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
        // NOT IMPLEMENTED (AMA-1932): no backend route
        throw APIError.notImplemented
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
