//
//  WorkoutParsingService.swift
//  AmakaFlow
//
//  Parses voice transcriptions into structured workouts using Claude API (via backend) (AMA-5)
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "WorkoutParsing")

/// Service for parsing natural language workout descriptions into structured workouts
@MainActor
class WorkoutParsingService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isParsing = false
    @Published private(set) var parsedWorkout: Workout?
    @Published private(set) var confidence: Double = 0
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var error: ParsingError?

    // MARK: - Properties

    private let apiService = APIService.shared

    // MARK: - Error Types

    enum ParsingError: LocalizedError {
        case notPaired
        case networkError(Error)
        case parsingFailed(String)
        case invalidResponse
        case emptyTranscription

        var errorDescription: String? {
            switch self {
            case .notPaired:
                return "Please connect to AmakaFlow first"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .parsingFailed(let message):
                return "Could not understand workout: \(message)"
            case .invalidResponse:
                return "Received invalid response from server"
            case .emptyTranscription:
                return "No text to parse. Please record a workout description."
            }
        }
    }

    // MARK: - Parsing

    /// Parse a transcription into a structured workout
    /// - Parameters:
    ///   - transcription: The text to parse
    ///   - sportHint: Optional hint about the sport type
    /// - Returns: The parsed workout
    func parse(transcription: String, sportHint: WorkoutSport? = nil) async throws -> Workout {
        guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParsingError.emptyTranscription
        }

        isParsing = true
        parsedWorkout = nil
        confidence = 0
        suggestions = []
        error = nil

        defer {
            isParsing = false
        }

        do {
            let response = try await apiService.parseVoiceWorkout(
                transcription: transcription,
                sportHint: sportHint
            )

            parsedWorkout = response.workout
            confidence = response.confidence
            suggestions = response.suggestions

            logger.info("Parsed workout: \(response.workout.name) with \(response.workout.intervals.count) intervals, confidence: \(response.confidence)")

            return response.workout
        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized:
                error = .notPaired
            case .networkError(let err):
                error = .networkError(err)
            case .serverErrorWithBody(_, let body):
                error = .parsingFailed(body)
            default:
                error = .parsingFailed(apiError.localizedDescription)
            }
            throw error!
        } catch {
            self.error = .networkError(error)
            throw ParsingError.networkError(error)
        }
    }

    /// Clear any parsed results
    func clear() {
        parsedWorkout = nil
        confidence = 0
        suggestions = []
        error = nil
    }
}
