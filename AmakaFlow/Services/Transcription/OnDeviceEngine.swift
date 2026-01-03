//
//  OnDeviceEngine.swift
//  AmakaFlow
//
//  On-device speech recognition using Apple's SFSpeechRecognizer (AMA-229)
//  Privacy-first: audio never leaves the device
//

import Foundation
import Speech

/// On-device transcription engine using Apple's SFSpeechRecognizer
/// Advantages: Free, private (no network), works offline
/// Limitations: Less accurate for accents, limited vocabulary boosting
@MainActor
final class OnDeviceEngine: TranscriptionEngine {
    // MARK: - TranscriptionEngine Protocol

    var providerName: String { "on_device" }

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    // MARK: - Properties

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentLanguage: String = "en-US"

    /// Whether on-device recognition is available (more private, no network)
    var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Initialization

    init(language: String = "en-US") {
        self.currentLanguage = language
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        language: String,
        keywords: [String]?
    ) async throws -> TranscriptionResult {
        // Update recognizer if language changed
        if language != currentLanguage {
            currentLanguage = language
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        }

        // Check availability
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }

        // Check permission
        guard PermissionManager.shared.hasSpeechRecognitionPermission else {
            throw TranscriptionError.permissionDenied
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)

        // Prefer on-device recognition for privacy
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Configure for workout descriptions
        request.shouldReportPartialResults = false // We want final result only
        request.addsPunctuation = true

        // Add custom vocabulary hints if available (iOS 17+)
        if #available(iOS 17.0, *), let keywords = keywords, !keywords.isEmpty {
            // Note: iOS 17+ supports contextual strings for boosting recognition
            request.contextualStrings = Array(keywords.prefix(100)) // Limit to 100 terms
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                // Prevent multiple resumes
                guard !hasResumed else { return }

                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error))
                    return
                }

                guard let result = result else { return }

                // Only process final result
                if result.isFinal {
                    hasResumed = true
                    let transcription = result.bestTranscription

                    if transcription.formattedString.isEmpty {
                        continuation.resume(throwing: TranscriptionError.noSpeechDetected)
                    } else {
                        // Calculate confidence from segment confidences
                        let confidence = self?.calculateConfidence(from: transcription) ?? 0.5

                        // Extract word timings
                        let wordTimings = transcription.segments.map { segment in
                            WordTiming(
                                word: segment.substring,
                                start: segment.timestamp,
                                end: segment.timestamp + segment.duration,
                                confidence: Double(segment.confidence)
                            )
                        }

                        let transcriptionResult = TranscriptionResult(
                            text: transcription.formattedString,
                            confidence: confidence,
                            words: wordTimings,
                            provider: .onDevice
                        )

                        continuation.resume(returning: transcriptionResult)
                    }
                }
            }
        }
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - Private Helpers

    /// Calculate overall confidence from segment confidences
    private func calculateConfidence(from transcription: SFTranscription) -> Double {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0.5 }

        // Weight by segment duration
        var totalWeight: Double = 0
        var weightedSum: Double = 0

        for segment in segments {
            let weight = segment.duration
            weightedSum += Double(segment.confidence) * weight
            totalWeight += weight
        }

        return totalWeight > 0 ? weightedSum / totalWeight : 0.5
    }
}

// MARK: - Language Support

extension OnDeviceEngine {
    /// Check if a specific language/locale is supported
    static func isLanguageSupported(_ languageCode: String) -> Bool {
        SFSpeechRecognizer.supportedLocales().contains { locale in
            locale.identifier == languageCode || locale.identifier.hasPrefix(languageCode.prefix(2) + "-")
        }
    }

    /// Get all supported locales for speech recognition
    static var supportedLocales: [Locale] {
        Array(SFSpeechRecognizer.supportedLocales())
    }
}
