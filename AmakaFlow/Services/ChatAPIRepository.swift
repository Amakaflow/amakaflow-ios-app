//
//  ChatAPIRepository.swift
//  AmakaFlow
//
//  AMA-1828: chat-api hosted endpoints split out of APIService.swift.
//  Implemented as `extension APIService` so call sites and the
//  APIServiceProviding conformance keep working unchanged.
//
//  AMA-1827 (this swap): all endpoints below now route through
//  `bffURL` (mobile-bff `/v1/*` paths) instead of chat-api directly.
//  Backend chat-api can be renamed without an iOS release. The BFF
//  proxies requests to chat-api with auth + X-Request-ID forwarding.
//
//  Endpoints in this file (all under bffURL = `…/v1`):
//    POST /coach/message              (sendCoachMessage)
//    POST /coach/fatigue-advice       (getFatigueAdvice)
//    GET  /coach/memories             (fetchCoachMemories)
//    POST /coach/suggest-workout      (suggestWorkout)
//    POST /coach/rpe-feedback         (postRPEFeedback)
//    GET  /gamification/xp            (fetchXP)
//    POST /nutrition/analyze-photo    (analyzePhoto)
//    GET  /nutrition/barcode/{code}   (lookupBarcode)
//    POST /nutrition/parse-text       (parseText)
//    GET  /nutrition/fueling-status   (getFuelingStatus)
//    POST /nutrition/protein-nudge/check (checkProteinNudge)
//

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

private struct GeneratedBFFTransport: ClientTransport {
    let base: URLSessionTransport
    let headers: [String: String]

    nonisolated func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        for (key, value) in headers {
            guard let name = HTTPField.Name(key) else { continue }
            request.headerFields[name] = value
        }
        return try await base.send(request, body: body, baseURL: baseURL, operationID: operationID)
    }
}

extension APIService {

    private func generatedBFFClient() async throws -> Client {
        guard let serverURL = URL(string: AppEnvironment.current.mobileBFFURL) else {
            throw APIError.invalidURL
        }
        let urlSession = (session as? URLSession) ?? .shared
        let baseTransport = URLSessionTransport(
            configuration: .init(session: urlSession, httpBodyProcessingMode: .buffered)
        )
        return Client(
            serverURL: serverURL,
            transport: GeneratedBFFTransport(base: baseTransport, headers: try await makeAuthHeaders())
        )
    }

    private static func generatedError(statusCode: Int) -> APIError {
        if statusCode == 401 { return .unauthorized }
        return .serverError(statusCode)
    }

    private static func generatedError<T: Encodable>(statusCode: Int, body: T) -> APIError {
        if statusCode == 401 { return .unauthorized }
        if let data = try? JSONEncoder().encode(body), let string = String(data: data, encoding: .utf8) {
            return .serverErrorWithBody(statusCode, string)
        }
        return .serverError(statusCode)
    }

    private static func coachTrainingContext(from context: CoachContext?) -> Components.Schemas.CoachTrainingContext? {
        guard
            let context,
            let recentWorkouts = context.recentWorkouts,
            !recentWorkouts.isEmpty,
            let currentDate = context.currentDate
        else { return nil }

        // recentWorkouts carries no per-workout dates (CoachContext.recentWorkouts is [String]); currentDate used as a placeholder session date.
        let completedSessions = recentWorkouts.map { workout in
            Components.Schemas.CoachCompletedSession(
                date: currentDate,
                notes: workout,
                title: workout,
                _type: "workout"
            )
        }

        return Components.Schemas.CoachTrainingContext(completedSessions: completedSessions)
    }

    // MARK: - Coach API (AMA-1147 / AMA-1133)

    func sendCoachMessage(message: String, context: CoachContext? = nil) async throws -> CoachResponse {
        let output = try await (try await generatedBFFClient()).v1CoachMessageV1CoachMessagePost(
            body: .json(.init(context: Self.coachTrainingContext(from: context), message: message))
        )
        switch output {
        case .ok(let response):
            let body = try response.body.json
            return CoachResponse(id: nil, message: body.message, suggestions: nil, actionItems: nil)
        case .unprocessableContent(let response):
            throw Self.generatedError(statusCode: 422, body: try response.body.json)
        case .serviceUnavailable(let response):
            throw Self.generatedError(statusCode: 503, body: try response.body.json)
        case .undocumented(let statusCode, _):
            let err = Self.generatedError(statusCode: statusCode)
            logError(endpoint: "/v1/coach/message", method: "POST", statusCode: statusCode, response: nil, error: err)
            throw err
        }
    }

    func getFatigueAdvice(fatigueScore: Double? = nil, loadHistory: [DailyLoad]? = nil) async throws -> FatigueAdvice {
        let output = try await (try await generatedBFFClient()).v1CoachFatigueAdviceV1CoachFatigueAdvicePost(
            body: .json(.init(question: Self.fatigueQuestion(fatigueScore: fatigueScore, loadHistory: loadHistory)))
        )
        switch output {
        case .ok(let response):
            return Self.fatigueAdvice(from: try response.body.json)
        case .unprocessableContent(let response):
            throw Self.generatedError(statusCode: 422, body: try response.body.json)
        case .serviceUnavailable(let response):
            throw Self.generatedError(statusCode: 503, body: try response.body.json)
        case .undocumented(let statusCode, _):
            let err = Self.generatedError(statusCode: statusCode)
            logError(endpoint: "/v1/coach/fatigue-advice", method: "POST", statusCode: statusCode, response: nil, error: err)
            throw err
        }
    }

    func fetchCoachMemories() async throws -> [CoachMemory] {
        let output = try await (try await generatedBFFClient()).v1CoachMemoriesV1CoachMemoriesGet()
        switch output {
        case .ok(let response):
            return try response.body.json.map(CoachMemory.init(generated:))
        case .unprocessableContent(let response):
            throw Self.generatedError(statusCode: 422, body: try response.body.json)
        case .serviceUnavailable(let response):
            throw Self.generatedError(statusCode: 503, body: try response.body.json)
        case .undocumented(let statusCode, _):
            let err = Self.generatedError(statusCode: statusCode)
            logError(endpoint: "/v1/coach/memories", method: "GET", statusCode: statusCode, response: nil, error: err)
            throw err
        }
    }

    private static func fatigueQuestion(fatigueScore: Double?, loadHistory: [DailyLoad]?) -> String {
        var parts = ["Assess my current training fatigue and recommend how I should adjust today's workout."]
        if let fatigueScore {
            parts.append("Current fatigue score: \(fatigueScore).")
        }
        if let loadHistory, !loadHistory.isEmpty {
            let history = loadHistory
                .map { "\($0.date): \($0.loadScore)" }
                .joined(separator: ", ")
            parts.append("Recent load history: \(history).")
        }
        return parts.joined(separator: " ")
    }

    private static func fatigueAdvice(from generated: Components.Schemas.FatigueAdviceResponse) -> FatigueAdvice {
        let combined = ([generated.likelyCause, generated.restRecommendation] + generated.immediateRecovery + generated.programmingSuggestions)
            .joined(separator: " ")
            .lowercased()
        let level: FatigueLevel
        if combined.contains("critical") || combined.contains("stop") || combined.contains("medical") {
            level = .critical
        } else if combined.contains("rest") || combined.contains("deload") || combined.contains("reduce") {
            level = .high
        } else if combined.contains("easy") || combined.contains("light") || combined.contains("moderate") {
            level = .moderate
        } else {
            level = .low
        }
        return FatigueAdvice(
            level: level,
            message: generated.restRecommendation,
            recommendations: generated.programmingSuggestions,
            suggestedRestDays: level == .high || level == .critical ? 1 : nil,
            recoveryActivities: generated.immediateRecovery
        )
    }

    // MARK: - XP + Level (AMA-1285)

    func fetchXP() async throws -> XPData {
        let url = URL(string: "\(bffURL)/gamification/xp")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in try await makeAuthHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = Self.makeDecoder()
        return try decoder.decode(XPData.self, from: data)
    }

    // MARK: - Nutrition (AMA-1412)

    func analyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse {
        let chatURL = bffURL
        guard let url = URL(string: "\(chatURL)/nutrition/analyze-photo") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        req.httpBody = try JSONEncoder().encode(["image_base64": imageBase64])
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(AnalyzePhotoAPIResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/analyze-photo", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse {
        let chatURL = bffURL
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        guard let url = URL(string: "\(chatURL)/nutrition/barcode/\(encoded)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(BarcodeNutritionAPIResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/barcode/\(code)", method: "GET",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func parseText(text: String) async throws -> ParseTextAPIResponse {
        let chatURL = bffURL
        guard let url = URL(string: "\(chatURL)/nutrition/parse-text") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        req.httpBody = try JSONEncoder().encode(["text": text])
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(ParseTextAPIResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/parse-text", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func getFuelingStatus() async throws -> FuelingStatusResponse {
        let chatURL = bffURL
        guard let url = URL(string: "\(chatURL)/nutrition/fueling-status") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(FuelingStatusResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/fueling-status", method: "GET",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func checkProteinNudge() async throws -> ProteinNudgeResponse {
        let chatURL = bffURL
        guard let url = URL(string: "\(chatURL)/nutrition/protein-nudge/check") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(ProteinNudgeResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/protein-nudge/check", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Coach Suggestions (AMA-1412)

    func suggestWorkout(request: SuggestWorkoutRequest) async throws -> SuggestWorkoutResponse {
        let output = try await (try await generatedBFFClient()).v1CoachSuggestWorkoutV1CoachSuggestWorkoutPost(
            body: .json(request)
        )
        switch output {
        case .ok(let response):
            return try response.body.json
        case .unprocessableContent(let response):
            throw Self.generatedError(statusCode: 422, body: try response.body.json)
        case .serviceUnavailable(let response):
            throw Self.generatedError(statusCode: 503, body: try response.body.json)
        case .undocumented(let statusCode, _):
            let err = Self.generatedError(statusCode: statusCode)
            logError(endpoint: "/v1/coach/suggest-workout", method: "POST", statusCode: statusCode, response: nil, error: err)
            throw err
        }
    }

    func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse {
        let output = try await (try await generatedBFFClient()).v1CoachRpeFeedbackV1CoachRpeFeedbackPost(
            body: .json(feedback)
        )
        switch output {
        case .ok(let response):
            return RPEFeedbackResponse(try response.body.json)
        case .unprocessableContent(let response):
            throw Self.generatedError(statusCode: 422, body: try response.body.json)
        case .serviceUnavailable(let response):
            throw Self.generatedError(statusCode: 503, body: try response.body.json)
        case .undocumented(let statusCode, _):
            let err = Self.generatedError(statusCode: statusCode)
            logError(endpoint: "/v1/coach/rpe-feedback", method: "POST", statusCode: statusCode, response: nil, error: err)
            throw err
        }
    }
}

private extension CoachMemory {
    init(generated: Components.Schemas.CoachMemoryResponse) {
        self.init(
            id: generated.id,
            content: generated.content,
            category: generated.category.rawValue,
            createdAt: generated.createdAt,
            relevance: generated.confidence
        )
    }
}
