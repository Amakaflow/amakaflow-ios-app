//
//  APIService.swift
//  AmakaFlow
//
//  AMA-1828: thin coordinator that retains the `APIService` class +
//  shared transport plumbing (baseURL, bffURL, URLSession, auth header
//  helpers) and continues to expose every endpoint via per-domain files
//  declared as `extension APIService` siblings:
//
//    • APITransport.swift           — JSON decoder + Sentry/log helper
//    • WorkoutAPIRepository.swift   — workouts, sync, completions, exports
//    • CoachAPIRepository.swift     — coach quick, planning, actions, prefs
//    • ChatAPIRepository.swift      — chat-api hosted (coach/nutrition/xp)
//    • DeviceAPIRepository.swift    — profile, push token, watch resend, privacy
//    • TelegramAPIRepository.swift  — telegram link-token + status
//    • IngestionAPIRepository.swift — voice parse, transcription, ingest, bulk
//    • SocialAPIRepository.swift    — feed, reactions, crews, leaderboards
//    • ProgramsAPIRepository.swift  — training programs + calendar sync
//
//  This file MUST stay ≤ 500 lines per the AMA-1817 epic acceptance
//  criterion #3. Add new endpoints to the appropriate domain file
//  (or create a new one) — do NOT grow this coordinator.
//

import Combine
import Foundation

/// Service for API communication with backend.
///
/// Retains a single `APIService.shared` instance so the existing
/// `APIServiceProviding` conformance (declared in
/// DependencyInjection/APIServiceProviding.swift) and all 19
/// `APIService.shared.foo()` call sites continue to work after the
/// AMA-1828 split. New endpoints belong on a domain extension file.
protocol APIURLSession: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: APIURLSession {}

class APIService {
    static let shared = APIService()

    var baseURL: String { AppEnvironment.current.mapperAPIURL }

    /// AMA-1820: BFF base for the 5 first-wave mobile-facing endpoints
    /// (workouts/complete, workouts/planned, sync/{pending,confirm,failed}).
    /// Always includes the `/v1` prefix the BFF mounts under, so callers
    /// just append `/workouts/complete` etc. — keeps call sites symmetric
    /// with the existing `baseURL` pattern. Per AMA-1826, request/response
    /// bodies remain hand-coded until the BFF declares typed schemas.
    var bffURL: String { "\(AppEnvironment.current.mobileBFFURL)/v1" }

    let session: APIURLSession
    let observabilityLogger: APIObservabilityLogging

    init(
        session: APIURLSession = URLSession.shared,
        observabilityLogger: APIObservabilityLogging = DefaultAPIObservabilityLogger.shared
    ) {
        self.session = session
        self.observabilityLogger = observabilityLogger
    }

    // MARK: - Auth Headers

    var authHeaders: [String: String] {
        var headers = ["Content-Type": "application/json"]
        if let token = PairingService.shared.getToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    func makeAuthHeaders() async -> [String: String] {
        var headers = ["Content-Type": "application/json"]
        guard AuthViewModel.shared.hasActiveSession else {
            return headers
        }

        do {
            if let token = try await AuthViewModel.shared.token() {
                headers["Authorization"] = "Bearer \(token)"
            } else {
                PairingService.shared.markAuthInvalid()
                print("[APIService] Clerk session did not return a token")
            }
        } catch {
            PairingService.shared.markAuthInvalid()
            print("[APIService] Failed to get Clerk token: \(error.localizedDescription)")
        }
        return headers
    }
}

// MARK: - DayState API Response Models (AMA-1150)

struct DayStateResponse: Codable {
    let date: String
    let readinessScore: Int
    let readinessLabel: String
    let sessions: [DayStateSessionResponse]
    let conflictAlert: DayStateConflictResponse?
}

struct DayStateSessionResponse: Codable {
    let id: String
    let name: String
    let scheduledTime: String?
    let sport: String
    let durationMinutes: Int?
    let isCompleted: Bool
    let isNext: Bool
}

struct DayStateConflictResponse: Codable {
    let message: String
    let severity: String
    let suggestedAction: String?
}

struct CoachQuickResponse: Codable {
    let answer: String
}

// MARK: - Completion History Responses

struct CompletionsListResponse: Codable {
    let success: Bool
    let completions: [WorkoutCompletion]
}

struct CompletionDetailWrappedResponse: Codable {
    let success: Bool
    let completion: WorkoutCompletionDetail
}

// MARK: - Profile Response

struct ProfileResponse: Codable {
    let success: Bool
    let profile: UserProfile
}

// MARK: - Pending Workouts Response

struct PendingWorkoutsResponse: Codable {
    let success: Bool
    let workouts: [Workout]
    let count: Int
}

// MARK: - Voice Workout Parse Response (AMA-5)

struct VoiceWorkoutParseResponse: Codable {
    let success: Bool
    let workout: Workout
    let confidence: Double
    let suggestions: [String]
}

// MARK: - Instagram Reel Ingestion Response (AMA-564)

struct IngestInstagramReelResponse: Codable {
    let title: String?
    let workoutType: String?
    let source: String?
}

// MARK: - Text Ingestion Response

struct IngestTextResponse: Codable {
    let name: String?
    let sport: String?
    let source: String?
}

// MARK: - Cloud Transcription Response (AMA-229)

struct CloudTranscriptionResponse: Codable {
    let text: String
    let confidence: Double
    let words: [CloudWordTiming]?
    let provider: String
    let durationMs: Int?
}

struct CloudWordTiming: Codable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double?
}

// MARK: - Personal Dictionary Response (AMA-229)

struct PersonalDictionaryResponse: Codable {
    let corrections: [String: String]
    let customTerms: [String]
}

// MARK: - Telegram Linking Responses

struct TelegramLinkTokenResponse: Codable, Equatable, Sendable {
    let token: String
    let deepLink: String
    let nativeLink: String
    let expiresInSeconds: Int
}

struct TelegramLinkStatusResponse: Codable, Equatable, Sendable {
    let linked: Bool
    let telegramId: Int?
    let usedAt: Date?
}

// MARK: - API Errors

/// AMA-1803 + AMA-1808: wrap an APIError with the X-Request-ID extracted
/// from the failing HTTPURLResponse so the user-facing Report button can
/// drop a Sentry breadcrumb correlated to AMA-1805's server-side capture
/// by request_id. Limited to the postWorkoutCompletion path for AMA-1803
/// P0; broader rollout (every APIService throw site) tracked under
/// AMA-1808 itself.
struct AnnotatedAPIError: Error, LocalizedError {
    let underlying: APIError
    let requestId: String?

    init(_ underlying: APIError, requestId: String? = nil) {
        self.underlying = underlying
        self.requestId = requestId
    }

    var errorDescription: String? { underlying.errorDescription }
}

enum APIError: LocalizedError {
    case notImplemented
    case invalidURL
    case invalidResponse

    /// Transport-level failure (offline, timeout, TLS, cancellation, etc.).
    case network(underlying: Error)
    /// Response body could not be decoded into the endpoint's expected model.
    case decoding(underlying: Error)
    case unauthorized
    case notFound
    /// Any non-2xx HTTP response that is not mapped to a more specific category.
    case server(status: Int)
    case unknown

    // Legacy cases kept while older repositories migrate onto APIService.request(...).
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int)
    case serverErrorWithBody(Int, String)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Feature not available yet"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .network(let error), .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decoding(let error), .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unauthorized:
            return "Session expired. Please reconnect."
        case .notFound:
            return "Resource not found"
        case .server(let code), .serverError(let code):
            return "Server error: \(code)"
        case .serverErrorWithBody(let code, let body):
            return "Server error \(code): \(body)"
        case .unknown:
            return "Unknown API error"
        }
    }

    var category: APIErrorCategory {
        switch self {
        case .notFound:
            return .notFound
        case .unauthorized:
            return .unauthorized
        case .server, .serverError, .serverErrorWithBody:
            return .server
        case .network, .networkError:
            return .network
        case .decoding, .decodingError:
            return .decoding
        case .notImplemented, .invalidURL, .invalidResponse, .unknown:
            return .unknown
        }
    }

    var sanitizedErrorType: String { category.rawValue }

    var userFacingMessage: String {
        if case .notImplemented = self {
            return "This feature isn’t available yet."
        }

        switch category {
        case .notFound:
            return "We couldn’t find that resource."
        case .unauthorized:
            return "Session expired. Please reconnect."
        case .server:
            return "The server had a problem. Please try again."
        case .network:
            return "Network error. Please check your connection."
        case .decoding:
            return "We received an unexpected response. Please try again."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

enum APIErrorCategory: String, Equatable {
    case notFound
    case unauthorized
    case server
    case network
    case decoding
    case unknown
}

struct APIErrorDisplayState: Identifiable, Equatable {
    let id = UUID()
    let category: APIErrorCategory
    let message: String

    init(error: Error) {
        let apiError = APIError.coerce(error)
        self.category = apiError.category
        self.message = apiError.userFacingMessage
    }
}

/// Reusable hook for ViewModels that want to expose typed API failures to Views.
/// Add `@Published var apiError: APIErrorDisplayState?` or own one of these and
/// call `present(_:)` in catch blocks instead of swallowing errors silently.
@MainActor
final class APIErrorState: ObservableObject {
    @Published var current: APIErrorDisplayState?

    func present(_ error: Error) {
        current = APIErrorDisplayState(error: error)
    }

    func clear() {
        current = nil
    }
}

extension APIError {
    static func coerce(_ error: Error) -> APIError {
        if let annotated = error as? AnnotatedAPIError {
            return annotated.underlying
        }
        return (error as? APIError) ?? .unknown
    }
}
