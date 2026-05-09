//
//  CoachAPIRepository.swift
//  AmakaFlow
//
//  AMA-1828: coach + planning + actions endpoints split out of
//  APIService.swift. Implemented as `extension APIService` so call sites
//  (WatchConnectivityManager, etc.) and APIServiceProviding conformance
//  keep working. Pure refactor.
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
        let url = URL(string: "\(baseURL)/api/v1/planning/day-state")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try Self.makeDecoder().decode(DayStateResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/api/v1/planning/day-state", method: "GET",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Ask the AI coach a quick question
    func askCoach(question: String) async throws -> String {
        let url = URL(string: "\(baseURL)/coach/quick")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        request.httpBody = try JSONEncoder().encode(["question": question])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let result = try Self.makeDecoder().decode(CoachQuickResponse.self, from: data)
            return result.answer
        case 401:
            throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/coach/quick", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    /// Resolve a training conflict (adjust or keep)
    func resolveConflict(action: String, message: String) async throws {
        let url = URL(string: "\(baseURL)/api/v1/planning/resolve-conflict")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        request.httpBody = try JSONEncoder().encode(["action": action, "message": message])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/api/v1/planning/resolve-conflict", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Planning API (AMA-1147 / AMA-1133)

    func fetchDayStates(from: String, to: String) async throws -> [DayState] {
        let url = URL(string: "\(baseURL)/api/v1/planning/day-states?from=\(from)&to=\(to)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200:
            return try Self.makeDecoder().decode([DayState].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func generateWeek(request genRequest: GenerateWeekRequest? = nil) async throws -> ProposedPlan {
        let url = URL(string: "\(baseURL)/api/v1/planning/generate-week")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let genRequest = genRequest {
            request.httpBody = try JSONEncoder().encode(genRequest)
        } else {
            request.httpBody = "{}".data(using: .utf8)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(ProposedPlan.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict] {
        let url = URL(string: "\(baseURL)/api/v1/planning/conflicts?start_date=\(startDate)&end_date=\(endDate)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode([Conflict].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func parseWorkoutText(text: String, context: String? = nil) async throws -> ParsedWorkout {
        let url = URL(string: "\(baseURL)/api/v1/planning/parse-workout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ParseWorkoutRequest(text: text, context: context))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(ParsedWorkout.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Actions API (AMA-1147 / AMA-1133)

    func fetchPendingActions() async throws -> [PendingAction] {
        let url = URL(string: "\(baseURL)/api/v1/actions/pending")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode([PendingAction].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func respondToAction(id: String, response actionResponse: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/api/v1/actions/\(id)/respond")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["response": actionResponse])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(ActionResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Analytics API (AMA-1147 / AMA-1133)

    func fetchShoeComparison() async throws -> [ShoeStats] {
        let url = URL(string: "\(baseURL)/api/v1/analytics/shoes")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode([ShoeStats].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Billing API (AMA-1147 / AMA-1133)

    func fetchSubscription() async throws -> Subscription {
        let url = URL(string: "\(baseURL)/api/v1/billing/subscription")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(Subscription.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Notification Preferences API (AMA-1147 / AMA-1133)

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        let url = URL(string: "\(baseURL)/api/v1/preferences/notifications")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(NotificationPreferences.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences {
        let url = URL(string: "\(baseURL)/api/v1/preferences/notifications")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(prefs)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(NotificationPreferences.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Volume Analytics (AMA-1414)

    func fetchVolumeAnalytics(startDate: String, endDate: String, granularity: String) async throws -> VolumeAnalyticsResponse {
        guard let url = URL(string: "\(baseURL)/progression/volume?start_date=\(startDate)&end_date=\(endDate)&granularity=\(granularity)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(VolumeAnalyticsResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/progression/volume", method: "GET", statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
