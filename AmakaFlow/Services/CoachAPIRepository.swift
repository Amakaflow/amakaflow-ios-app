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
//    GET  /api/v1/planning/day-state            (fetchDayState)
//    POST /coach/quick                          (askCoach)
//    POST /api/v1/planning/resolve-conflict     (resolveConflict)
//    GET  /api/v1/planning/day-states           (fetchDayStates)
//    POST /api/v1/planning/generate-week        (generateWeek)
//    GET  /api/v1/planning/conflicts            (detectConflicts)
//    POST /api/v1/planning/parse-workout        (parseWorkoutText)
//    GET  /api/v1/actions/pending               (fetchPendingActions)
//    POST /api/v1/actions/{id}/respond          (respondToAction)
//    GET  /api/v1/analytics/shoes               (fetchShoeComparison)
//    GET  /api/v1/billing/subscription          (fetchSubscription)
//    GET  /api/v1/preferences/notifications     (fetchNotificationPreferences)
//    PUT  /api/v1/preferences/notifications     (updateNotificationPreferences)
//    GET  /progression/volume                   (fetchVolumeAnalytics)
//

import Foundation

extension APIService {

    // MARK: - DayState / Coach / Conflict (AMA-1150)

    /// Fetch today's DayState from the planning API
    func fetchDayState() async throws -> DayStateResponse {
        let request = try await makeAPIRequest(
            path: "/api/v1/planning/day-state",
            method: "GET"
        )
        return try await self.request(request, decode: DayStateResponse.self, successStatusCodes: 200...200)
    }

    /// Ask the AI coach a quick question
    func askCoach(question: String) async throws -> String {
        let request = try await makeAPIRequest(
            path: "/coach/quick",
            method: "POST",
            body: try encodeJSONBody(["question": question])
        )
        let result = try await self.request(request, decode: CoachQuickResponse.self, successStatusCodes: 200...200)
        return result.answer
    }

    /// Resolve a training conflict (adjust or keep)
    func resolveConflict(action: String, message: String) async throws {
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
            path: "/api/v1/planning/day-states",
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
            path: "/api/v1/planning/generate-week",
            method: "POST",
            body: body
        )
        return try await self.request(request, decode: ProposedPlan.self, successStatusCodes: 200...200)
    }

    func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict] {
        let request = try await makeAPIRequest(
            path: "/api/v1/planning/conflicts",
            queryItems: [
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate)
            ],
            method: "GET"
        )
        return try await self.request(request, decode: [Conflict].self, successStatusCodes: 200...200)
    }

    func parseWorkoutText(text: String, context: String? = nil) async throws -> ParsedWorkout {
        let request = try await makeAPIRequest(
            path: "/api/v1/planning/parse-workout",
            method: "POST",
            body: try encodeJSONBody(ParseWorkoutRequest(text: text, context: context))
        )
        return try await self.request(request, decode: ParsedWorkout.self, successStatusCodes: 200...200)
    }

    // MARK: - Actions API (AMA-1147 / AMA-1133)

    func fetchPendingActions() async throws -> [PendingAction] {
        let request = try await makeAPIRequest(
            path: "/api/v1/actions/pending",
            method: "GET"
        )
        return try await self.request(request, decode: [PendingAction].self, successStatusCodes: 200...200)
    }

    func respondToAction(id: String, response actionResponse: String) async throws -> ActionResponse {
        let request = try await makeAPIRequest(
            path: "/api/v1/actions/\(id)/respond",
            method: "POST",
            body: try encodeJSONBody(["response": actionResponse])
        )
        return try await self.request(request, decode: ActionResponse.self, successStatusCodes: 200...200)
    }

    // MARK: - Analytics API (AMA-1147 / AMA-1133)

    func fetchShoeComparison() async throws -> [ShoeStats] {
        let request = try await makeAPIRequest(
            path: "/api/v1/analytics/shoes",
            method: "GET"
        )
        return try await self.request(request, decode: [ShoeStats].self, successStatusCodes: 200...200)
    }

    // MARK: - Billing API (AMA-1147 / AMA-1133)

    func fetchSubscription() async throws -> Subscription {
        let request = try await makeAPIRequest(
            path: "/api/v1/billing/subscription",
            method: "GET"
        )
        return try await self.request(request, decode: Subscription.self, successStatusCodes: 200...200)
    }

    // MARK: - Notification Preferences API (AMA-1147 / AMA-1133)

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        let request = try await makeAPIRequest(
            path: "/api/v1/preferences/notifications",
            method: "GET"
        )
        return try await self.request(request, decode: NotificationPreferences.self, successStatusCodes: 200...200)
    }

    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences {
        let request = try await makeAPIRequest(
            path: "/api/v1/preferences/notifications",
            method: "PUT",
            body: try encodeJSONBody(prefs)
        )
        return try await self.request(request, decode: NotificationPreferences.self, successStatusCodes: 200...200)
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
