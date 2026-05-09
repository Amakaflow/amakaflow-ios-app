//
//  ChatAPIRepository.swift
//  AmakaFlow
//
//  AMA-1828: chat-api hosted endpoints split out of APIService.swift.
//  Implemented as `extension APIService` so call sites and the
//  APIServiceProviding conformance keep working unchanged.
//
//  Per AMA-1828 spec: all endpoints in this file currently route through
//  `AppEnvironment.current.chatAPIURL`. AMA-1827 will swap them to
//  `bffURL` in a follow-up — do NOT change chatAPIURL behaviour here.
//
//  Endpoints in this file:
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

extension APIService {

    // MARK: - Coach API (AMA-1147 / AMA-1133)

    func sendCoachMessage(message: String, context: CoachContext? = nil) async throws -> CoachResponse {
        let chatURL = AppEnvironment.current.chatAPIURL
        let url = URL(string: "\(chatURL)/coach/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CoachMessageRequest(message: message, context: context))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(CoachResponse.self, from: data)
        case 401: throw APIError.unauthorized
        case 429:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverErrorWithBody(429, body)
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func getFatigueAdvice(fatigueScore: Double? = nil, loadHistory: [DailyLoad]? = nil) async throws -> FatigueAdvice {
        let chatURL = AppEnvironment.current.chatAPIURL
        let url = URL(string: "\(chatURL)/coach/fatigue-advice")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = await makeAuthHeaders()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(FatigueAdviceRequest(currentFatigueScore: fatigueScore, recentLoadHistory: loadHistory))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode(FatigueAdvice.self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func fetchCoachMemories() async throws -> [CoachMemory] {
        let chatURL = AppEnvironment.current.chatAPIURL
        let url = URL(string: "\(chatURL)/coach/memories")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = await makeAuthHeaders()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200: return try Self.makeDecoder().decode([CoachMemory].self, from: data)
        case 401: throw APIError.unauthorized
        default: throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - XP + Level (AMA-1285)

    func fetchXP() async throws -> XPData {
        let url = URL(string: "\(AppEnvironment.current.chatAPIURL)/gamification/xp")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in await makeAuthHeaders() {
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
        let chatURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(chatURL)/nutrition/analyze-photo") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = await makeAuthHeaders()
        req.httpBody = try JSONEncoder().encode(["image_base64": imageBase64])
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(AnalyzePhotoAPIResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/analyze-photo", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse {
        let chatURL = AppEnvironment.current.chatAPIURL
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        guard let url = URL(string: "\(chatURL)/nutrition/barcode/\(encoded)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(BarcodeNutritionAPIResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/barcode/\(code)", method: "GET",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func parseText(text: String) async throws -> ParseTextAPIResponse {
        let chatURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(chatURL)/nutrition/parse-text") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = await makeAuthHeaders()
        req.httpBody = try JSONEncoder().encode(["text": text])
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ParseTextAPIResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/parse-text", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func getFuelingStatus() async throws -> FuelingStatusResponse {
        let chatURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(chatURL)/nutrition/fueling-status") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(FuelingStatusResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/nutrition/fueling-status", method: "GET",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func checkProteinNudge() async throws -> ProteinNudgeResponse {
        let chatURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(chatURL)/nutrition/protein-nudge/check") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ProteinNudgeResponse.self, from: data)
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
        let chatURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(chatURL)/coach/suggest-workout") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            return try APIService.makeDecoder().decode(SuggestWorkoutResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/coach/suggest-workout", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse {
        let chatURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(chatURL)/coach/rpe-feedback") else { throw APIError.invalidURL }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = await makeAuthHeaders()
        req.httpBody = try encoder.encode(feedback)
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            return try APIService.makeDecoder().decode(RPEFeedbackResponse.self, from: data)
        case 401: throw APIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/coach/rpe-feedback", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
