//
//  TranscriptionEngine.swift
//  AmakaFlow
//
//  Protocol and models for multi-provider voice transcription (AMA-229)
//

import Foundation

// MARK: - Transcription Provider

/// Available transcription providers
enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case onDevice = "on_device"      // Apple SFSpeechRecognizer (free, private)
    case deepgram = "deepgram"       // Cloud - best accuracy (~$0.01/min)
    case assemblyai = "assemblyai"   // Cloud - budget option (~$0.005/min)
    case smart = "smart"             // On-device first, cloud fallback if low confidence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: return "On-Device"
        case .deepgram: return "Deepgram"
        case .assemblyai: return "AssemblyAI"
        case .smart: return "Smart"
        }
    }

    var description: String {
        switch self {
        case .onDevice:
            return "Privacy-first. Audio never leaves device."
        case .deepgram:
            return "Best accuracy & accent handling."
        case .assemblyai:
            return "Good accuracy, lowest cost."
        case .smart:
            return "On-device first, cloud fallback if needed."
        }
    }

    var costInfo: String {
        switch self {
        case .onDevice: return "FREE"
        case .deepgram: return "~$0.01/min"
        case .assemblyai: return "~$0.005/min"
        case .smart: return "AUTO"
        }
    }

    var bestFor: String {
        switch self {
        case .onDevice: return "Clear speech, US English"
        case .deepgram: return "Accents, noisy environments"
        case .assemblyai: return "Budget-conscious users"
        case .smart: return "Most users (recommended)"
        }
    }

    var isCloud: Bool {
        switch self {
        case .onDevice: return false
        case .deepgram, .assemblyai: return true
        case .smart: return false // Primary is on-device
        }
    }
}

// MARK: - Accent Region

/// Supported accent/language regions for transcription
enum AccentRegion: String, Codable, CaseIterable, Identifiable {
    case enUS = "en-US"
    case enGB = "en-GB"
    case enAU = "en-AU"
    case enIN = "en-IN"
    case enZA = "en-ZA"
    case enNG = "en-NG"
    case enOther = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .enUS: return "US English"
        case .enGB: return "UK English"
        case .enAU: return "Australian English"
        case .enIN: return "Indian English"
        case .enZA: return "South African English"
        case .enNG: return "Nigerian English"
        case .enOther: return "Other accented English"
        }
    }
}

// MARK: - Transcription Result

/// Result from a transcription operation
struct TranscriptionResult {
    let text: String
    let confidence: Double
    let words: [WordTiming]?
    let provider: TranscriptionProvider

    /// Whether this result is considered high confidence
    var isHighConfidence: Bool {
        confidence >= 0.80
    }
}

/// Word-level timing information (when available)
struct WordTiming: Codable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double?
}

// MARK: - Transcription Error

enum TranscriptionError: LocalizedError {
    case notAvailable
    case permissionDenied
    case recognitionFailed(Error)
    case noSpeechDetected
    case cancelled
    case networkError(Error)
    case apiError(Int, String)
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Speech recognition is not available on this device"
        case .permissionDenied:
            return "Speech recognition permission is required"
        case .recognitionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .noSpeechDetected:
            return "No speech was detected in the recording"
        case .cancelled:
            return "Transcription was cancelled"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format for transcription"
        }
    }
}

// MARK: - Transcription Engine Protocol

/// Protocol for transcription engines (on-device and cloud)
protocol TranscriptionEngine {
    /// Unique provider name
    var providerName: String { get }

    /// Transcribe audio data to text
    /// - Parameters:
    ///   - audioURL: URL of the audio file to transcribe
    ///   - language: Language/accent code (e.g., "en-US")
    ///   - keywords: Optional fitness keywords for boosting
    /// - Returns: Transcription result with text and confidence
    func transcribe(
        audioURL: URL,
        language: String,
        keywords: [String]?
    ) async throws -> TranscriptionResult

    /// Whether this engine is currently available
    var isAvailable: Bool { get }

    /// Cancel any in-progress transcription
    func cancel()
}

// MARK: - Default Implementations

extension TranscriptionEngine {
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, language: "en-US", keywords: nil)
    }
}
