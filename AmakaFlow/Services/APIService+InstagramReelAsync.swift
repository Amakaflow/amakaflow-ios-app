//
//  APIService+InstagramReelAsync.swift
//  AmakaFlow
//
//  AMA-2323 / docs#46 — Instagram reel async start + status poll with
//  transient transport retry (NSURLErrorNetworkConnectionLost / −1005).
//

import Foundation

extension APIService {
    /// Short per-request timeouts for async start + poll — survives app backgrounding.
    private static let socialAsyncStartTimeoutInterval: TimeInterval = 30
    private static let socialAsyncPollTimeoutInterval: TimeInterval = 15
    private static let socialAsyncPollIntervalNanoseconds: UInt64 = 1_500_000_000
    private static let socialAsyncPollDeadlineSeconds: TimeInterval = 180
    /// Initial backoff after a transient poll transport blip (AMA-2323).
    /// Never shorter than the healthy poll interval — failure must not accelerate.
    private static let socialAsyncPollBackoffNs: UInt64 = socialAsyncPollIntervalNanoseconds
    /// Give up after this many consecutive transport blips (ticket: surface network
    /// when consecutive polls keep failing). A single −1005 still survives.
    private static let socialAsyncPollMaxTransient = 8

    // MARK: - Test hooks (AMA-2323)

    #if DEBUG
    /// Overrides for unit tests — keep production defaults when nil.
    static var socialAsyncPollDeadlineSecondsForTests: TimeInterval?
    static var socialAsyncPollIntervalNsForTests: UInt64?
    static var socialAsyncPollBackoffNsForTests: UInt64?
    static var socialAsyncPollMaxTransientForTests: Int?

    static func resetSocialAsyncPollTimingOverridesForTests() {
        socialAsyncPollDeadlineSecondsForTests = nil
        socialAsyncPollIntervalNsForTests = nil
        socialAsyncPollBackoffNsForTests = nil
        socialAsyncPollMaxTransientForTests = nil
    }
    #endif

    private static var resolvedPollDeadlineSeconds: TimeInterval {
        #if DEBUG
        return socialAsyncPollDeadlineSecondsForTests ?? socialAsyncPollDeadlineSeconds
        #else
        return socialAsyncPollDeadlineSeconds
        #endif
    }

    private static var resolvedPollIntervalNanoseconds: UInt64 {
        #if DEBUG
        return socialAsyncPollIntervalNsForTests ?? socialAsyncPollIntervalNanoseconds
        #else
        return socialAsyncPollIntervalNanoseconds
        #endif
    }

    private static var resolvedTransientBackoffNanoseconds: UInt64 {
        #if DEBUG
        return socialAsyncPollBackoffNsForTests ?? socialAsyncPollBackoffNs
        #else
        return socialAsyncPollBackoffNs
        #endif
    }

    private static var resolvedMaxConsecutiveTransientFailures: Int {
        #if DEBUG
        return socialAsyncPollMaxTransientForTests ?? socialAsyncPollMaxTransient
        #else
        return socialAsyncPollMaxTransient
        #endif
    }

    /// docs#46 — POST /ingest/instagram_reel/async then poll GET /tasks/{id}/status.
    func ingestInstagramReelAsync(url: String) async throws -> Data {
        let taskId = try await startInstagramReelAsyncTask(url: url)
        return try await pollInstagramReelTask(taskId: taskId)
    }

    private func startInstagramReelAsyncTask(url: String) async throws -> String {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        guard let startURL = URL(string: "\(ingestorURL)/ingest/instagram_reel/async") else {
            throw APIError.invalidURL
        }

        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.timeoutInterval = Self.socialAsyncStartTimeoutInterval
        startRequest.allHTTPHeaderFields = try await makeAuthHeaders()
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: ["url": url])

        print("[APIService] ingestInstagramReelAsync - \(startURL.absoluteString)")

        let (startData, startResponse) = try await session.data(for: startRequest)
        _ = try await Self.validateSocialIngestResponse(
            data: startData,
            response: startResponse,
            endpoint: "/ingest/instagram_reel/async"
        )

        guard
            let startJSON = try JSONSerialization.jsonObject(with: startData) as? [String: Any],
            let taskId = startJSON["task_id"] as? String,
            !taskId.isEmpty
        else {
            throw APIError.invalidResponse
        }
        return taskId
    }

    private func pollInstagramReelTask(taskId: String) async throws -> Data {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let deadline = Date().addingTimeInterval(Self.resolvedPollDeadlineSeconds)
        var consecutiveTransientFailures = 0

        while Date() < deadline {
            if Task.isCancelled { throw CancellationError() }
            do {
                if let data = try await fetchInstagramReelTaskStatus(ingestorURL: ingestorURL, taskId: taskId) {
                    return data
                }
                consecutiveTransientFailures = 0
                try await Task.sleep(nanoseconds: Self.resolvedPollIntervalNanoseconds)
            } catch {
                if CTAError.isCancellation(error) {
                    throw error
                }
                guard Self.isTransientPollTransportError(error) else {
                    throw error
                }
                // Idempotent status GETs: one keep-alive drop (−1005) must not abort
                // a long MEDIA-route import still running on the server (AMA-2323).
                consecutiveTransientFailures += 1
                print(
                    "[APIService] pollInstagramReelTask transient poll error "
                        + "(\(consecutiveTransientFailures)/\(Self.resolvedMaxConsecutiveTransientFailures)) — retrying: \(error)"
                )
                if consecutiveTransientFailures >= Self.resolvedMaxConsecutiveTransientFailures {
                    throw error
                }
                let shift = min(consecutiveTransientFailures - 1, 3)
                let exponential = Self.resolvedTransientBackoffNanoseconds << shift
                let sleepNs = max(Self.resolvedPollIntervalNanoseconds, exponential)
                try await Task.sleep(nanoseconds: sleepNs)
            }
        }

        // Prefer honest "still running" copy — the server task may still complete.
        throw APIError.serverErrorWithBody(
            504,
            "Import is still running — open the app again in a minute, or retry."
        )
    }

    /// Transport blips on poll GETs — reuse CTAError's connectivity-only list.
    private static func isTransientPollTransportError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return CTAError.isTransientURLError(urlError.code)
        }
        if case APIError.networkError(let underlying) = error,
           let urlError = underlying as? URLError {
            return CTAError.isTransientURLError(urlError.code)
        }
        if case APIError.network(let underlying) = error,
           let urlError = underlying as? URLError {
            return CTAError.isTransientURLError(urlError.code)
        }
        return false
    }

    /// Returns workout JSON when complete; `nil` when still queued/processing.
    private func fetchInstagramReelTaskStatus(ingestorURL: String, taskId: String) async throws -> Data? {
        guard let statusURL = URL(string: "\(ingestorURL)/tasks/\(taskId)/status") else {
            throw APIError.invalidURL
        }
        var statusRequest = URLRequest(url: statusURL)
        statusRequest.httpMethod = "GET"
        statusRequest.timeoutInterval = Self.socialAsyncPollTimeoutInterval
        statusRequest.allHTTPHeaderFields = try await makeAuthHeaders()

        let (statusData, statusResponse) = try await session.data(for: statusRequest)
        guard let http = statusResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverError(http.statusCode)
        }

        guard
            let statusJSON = try JSONSerialization.jsonObject(with: statusData) as? [String: Any],
            let status = statusJSON["status"] as? String
        else {
            throw APIError.invalidResponse
        }

        switch status {
        case "completed":
            return try Self.workoutDataFromAsyncTaskResult(statusJSON["result"])
        case "failed":
            // AMA-2470: the task body carries the same typed `failure` envelope as
            // the sync path. Throw it directly so poll failures branch on a code
            // instead of on prose; `error` remains the fallback for older servers.
            let message = (statusJSON["error"] as? String) ?? "Instagram reel import failed"
            if let typed = IngestFailure.decode(fromEnvelope: statusJSON) {
                throw SocialImportFailure.ingest(typed)
            }
            throw APIError.serverErrorWithBody(400, message)
        default:
            return nil
        }
    }

    private static func workoutDataFromAsyncTaskResult(_ result: Any?) throws -> Data {
        guard let result else { throw APIError.invalidResponse }
        if let envelope = result as? [String: Any] {
            if let nested = envelope["workout"] as? [String: Any] {
                return try JSONSerialization.data(withJSONObject: nested)
            }
            if envelope["blocks"] != nil || envelope["title"] != nil {
                return try JSONSerialization.data(withJSONObject: envelope)
            }
        }
        throw APIError.invalidResponse
    }
}
