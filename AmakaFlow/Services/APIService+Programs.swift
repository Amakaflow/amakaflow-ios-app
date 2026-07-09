//
//  APIService+Programs.swift
//  AmakaFlow
//
//  AMA-1828: training-programs + calendar-sync endpoints split out of
//  APIService.swift. Implemented as `extension APIService` so call sites
//  and APIServiceProviding conformance keep working unchanged.
//

import Foundation

extension APIService {

    // MARK: - Training Programs (AMA-1231)

    func fetchPrograms(status: String) async throws -> ProgramsResponse {
        guard let url = URL(string: "\(baseURL)/programs?status=\(status)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(httpResponse.statusCode)
        }
        return try APIService.makeDecoder().decode(ProgramsResponse.self, from: data)
    }

    func fetchProgramDetail(id: String) async throws -> TrainingProgram {
        guard let url = URL(string: "\(baseURL)/programs/\(id)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.serverError(httpResponse.statusCode)
        }
        return try APIService.makeDecoder().decode(TrainingProgram.self, from: data)
    }

    // MARK: - Program Generation (AMA-1413)

    func generateProgram(request: ProgramGenerationRequest) async throws -> ProgramGenerationResponse {
        guard let url = URL(string: "\(baseURL)/programs/generate") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(request)
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/programs/generate", method: "POST",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
        return try APIService.makeDecoder().decode(ProgramGenerationResponse.self, from: data)
    }

    func fetchGenerationStatus(jobId: String) async throws -> ProgramGenerationStatus {
        guard let url = URL(string: "\(baseURL)/programs/generate/\(jobId)/status") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/programs/generate/\(jobId)/status", method: "GET",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
        return try APIService.makeDecoder().decode(ProgramGenerationStatus.self, from: data)
    }

    func updateProgramStatus(id: String, status: String) async throws {
        guard let url = URL(string: "\(baseURL)/training-programs/\(id)/status") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/training-programs/\(id)/status", method: "PATCH",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func updateProgramProgress(id: String, currentWeek: Int) async throws {
        guard let url = URL(string: "\(baseURL)/training-programs/\(id)/progress") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        req.httpBody = try JSONSerialization.data(withJSONObject: ["current_week": currentWeek])
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/training-programs/\(id)/progress", method: "PATCH",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func deleteProgram(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/training-programs/\(id)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/training-programs/\(id)", method: "DELETE",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func completeWorkout(workoutId: String) async throws {
        guard let url = URL(string: "\(baseURL)/training-programs/workouts/\(workoutId)/complete") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logError(endpoint: "/training-programs/workouts/\(workoutId)/complete", method: "PATCH",
                     statusCode: httpResponse.statusCode, response: body, error: nil)
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Calendar Sync (AMA-1238)

    func fetchConnectedCalendars() async throws -> [ConnectedCalendar] {
        let calURL = AppEnvironment.current.calendarAPIURL
        guard let url = URL(string: "\(calURL)/calendars/connected") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try APIService.makeDecoder().decode([ConnectedCalendar].self, from: data)
    }

    func connectCalendar(provider: String) async throws -> String {
        let calURL = AppEnvironment.current.calendarAPIURL
        guard let url = URL(string: "\(calURL)/calendars/connect") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let body = ["provider": provider]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct ConnectResponse: Codable { let url: String }
        let result = try APIService.makeDecoder().decode(ConnectResponse.self, from: data)
        return result.url
    }

    func syncCalendar(calendarId: String) async throws -> CalendarSyncResponse {
        let calURL = AppEnvironment.current.calendarAPIURL
        guard let url = URL(string: "\(calURL)/calendars/\(calendarId)/sync") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct SyncAPIResponse: Codable { let syncedEvents: Int? }
        let result = try APIService.makeDecoder().decode(SyncAPIResponse.self, from: data)
        return CalendarSyncResponse(syncedEvents: result.syncedEvents)
    }

    func disconnectCalendar(calendarId: String) async throws {
        let calURL = AppEnvironment.current.calendarAPIURL
        guard let url = URL(string: "\(calURL)/calendars/\(calendarId)/disconnect") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = try await makeAuthHeaders()
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}
