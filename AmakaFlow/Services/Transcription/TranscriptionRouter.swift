//
//  TranscriptionRouter.swift
//  AmakaFlow
//
//  Smart routing between transcription providers (AMA-229)
//  Handles provider selection, fallback logic, and vocabulary boosting
//

import Foundation
import Combine

/// Routes transcription requests to the appropriate engine based on settings
/// Supports smart fallback from on-device to cloud if confidence is low
@MainActor
final class TranscriptionRouter: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isTranscribing = false
    @Published private(set) var lastResult: TranscriptionResult?
    @Published private(set) var lastError: TranscriptionError?

    // MARK: - Settings

    @Published var preferredProvider: TranscriptionProvider {
        didSet { saveSettings() }
    }

    @Published var accentRegion: AccentRegion {
        didSet { saveSettings() }
    }

    @Published var cloudFallbackEnabled: Bool {
        didSet { saveSettings() }
    }

    @Published var fallbackProvider: TranscriptionProvider {
        didSet { saveSettings() }
    }

    // MARK: - Properties

    private let onDeviceEngine: OnDeviceEngine
    private let deepgramEngine: CloudTranscriptionEngine
    private let assemblyAIEngine: CloudTranscriptionEngine

    private let fitnessVocabulary: FitnessVocabulary
    private let personalDictionary: PersonalDictionary

    /// Confidence threshold for triggering cloud fallback in smart mode
    private let confidenceThreshold: Double = 0.80

    private let settingsKey = "transcription_settings"

    // MARK: - Singleton

    static let shared = TranscriptionRouter()

    // MARK: - Initialization

    private init() {
        // Load saved settings
        let settings = TranscriptionRouter.loadSettings()
        self.preferredProvider = settings.provider
        self.accentRegion = settings.accent
        self.cloudFallbackEnabled = settings.cloudFallback
        self.fallbackProvider = settings.fallbackProvider

        // Initialize engines
        self.onDeviceEngine = OnDeviceEngine(language: settings.accent.rawValue)
        self.deepgramEngine = CloudTranscriptionEngine.deepgram()
        self.assemblyAIEngine = CloudTranscriptionEngine.assemblyAI()

        // Initialize vocabulary services
        self.fitnessVocabulary = FitnessVocabulary.shared
        self.personalDictionary = PersonalDictionary.shared
    }

    // MARK: - Transcription

    /// Transcribe audio using configured provider(s)
    /// - Parameters:
    ///   - audioURL: URL of the audio file to transcribe
    ///   - providerOverride: Optional provider to use instead of settings
    /// - Returns: Transcription result with text and confidence
    func transcribe(
        audioURL: URL,
        providerOverride: TranscriptionProvider? = nil
    ) async throws -> TranscriptionResult {
        isTranscribing = true
        lastError = nil

        defer { isTranscribing = false }

        let provider = providerOverride ?? preferredProvider
        let keywords = buildKeywordList()

        do {
            let result: TranscriptionResult

            switch provider {
            case .onDevice:
                result = try await transcribeOnDevice(audioURL: audioURL, keywords: keywords)

            case .deepgram:
                result = try await transcribeCloud(
                    audioURL: audioURL,
                    engine: deepgramEngine,
                    keywords: keywords
                )

            case .assemblyai:
                result = try await transcribeCloud(
                    audioURL: audioURL,
                    engine: assemblyAIEngine,
                    keywords: keywords
                )

            case .smart:
                result = try await transcribeSmart(audioURL: audioURL, keywords: keywords)
            }

            // Apply personal dictionary corrections
            let correctedResult = applyPersonalDictionary(to: result)

            lastResult = correctedResult
            return correctedResult

        } catch let error as TranscriptionError {
            lastError = error
            throw error
        } catch {
            let transcriptionError = TranscriptionError.recognitionFailed(error)
            lastError = transcriptionError
            throw transcriptionError
        }
    }

    /// Cancel any in-progress transcription
    func cancel() {
        onDeviceEngine.cancel()
        deepgramEngine.cancel()
        assemblyAIEngine.cancel()
        isTranscribing = false
    }

    // MARK: - Private Transcription Methods

    private func transcribeOnDevice(
        audioURL: URL,
        keywords: [String]
    ) async throws -> TranscriptionResult {
        try await onDeviceEngine.transcribe(
            audioURL: audioURL,
            language: accentRegion.rawValue,
            keywords: keywords
        )
    }

    private func transcribeCloud(
        audioURL: URL,
        engine: CloudTranscriptionEngine,
        keywords: [String]
    ) async throws -> TranscriptionResult {
        try await engine.transcribe(
            audioURL: audioURL,
            language: accentRegion.rawValue,
            keywords: keywords
        )
    }

    /// Smart transcription: on-device first, cloud fallback if low confidence
    private func transcribeSmart(
        audioURL: URL,
        keywords: [String]
    ) async throws -> TranscriptionResult {
        // Try on-device first
        let onDeviceResult: TranscriptionResult
        do {
            onDeviceResult = try await transcribeOnDevice(audioURL: audioURL, keywords: keywords)
        } catch {
            // On-device failed, try cloud immediately
            if cloudFallbackEnabled {
                return try await transcribeWithFallbackProvider(audioURL: audioURL, keywords: keywords)
            }
            throw error
        }

        // Check confidence threshold
        if onDeviceResult.isHighConfidence || !cloudFallbackEnabled {
            return onDeviceResult
        }

        // Low confidence - try cloud fallback
        print("[TranscriptionRouter] On-device confidence \(String(format: "%.1f%%", onDeviceResult.confidence * 100)) below threshold, trying cloud fallback")

        do {
            let cloudResult = try await transcribeWithFallbackProvider(audioURL: audioURL, keywords: keywords)

            // Use cloud result if it's better
            if cloudResult.confidence > onDeviceResult.confidence {
                print("[TranscriptionRouter] Using cloud result (confidence: \(String(format: "%.1f%%", cloudResult.confidence * 100)))")
                return cloudResult
            } else {
                print("[TranscriptionRouter] On-device result was better, keeping it")
                return onDeviceResult
            }
        } catch {
            // Cloud failed, return on-device result
            print("[TranscriptionRouter] Cloud fallback failed: \(error), using on-device result")
            return onDeviceResult
        }
    }

    private func transcribeWithFallbackProvider(
        audioURL: URL,
        keywords: [String]
    ) async throws -> TranscriptionResult {
        let engine = fallbackProvider == .assemblyai ? assemblyAIEngine : deepgramEngine
        return try await transcribeCloud(audioURL: audioURL, engine: engine, keywords: keywords)
    }

    // MARK: - Vocabulary & Dictionary

    private func buildKeywordList() -> [String] {
        var keywords = fitnessVocabulary.allKeywords
        keywords.append(contentsOf: personalDictionary.customTerms)
        return keywords
    }

    private func applyPersonalDictionary(to result: TranscriptionResult) -> TranscriptionResult {
        let correctedText = personalDictionary.applyCorrections(to: result.text)

        if correctedText != result.text {
            return TranscriptionResult(
                text: correctedText,
                confidence: result.confidence,
                words: result.words,
                provider: result.provider
            )
        }

        return result
    }

    // MARK: - Settings Persistence

    private struct SavedSettings: Codable {
        let provider: TranscriptionProvider
        let accent: AccentRegion
        let cloudFallback: Bool
        let fallbackProvider: TranscriptionProvider
    }

    private static func loadSettings() -> SavedSettings {
        guard let data = UserDefaults.standard.data(forKey: "transcription_settings"),
              let settings = try? JSONDecoder().decode(SavedSettings.self, from: data) else {
            // Return defaults
            return SavedSettings(
                provider: .smart,
                accent: .enUS,
                cloudFallback: true,
                fallbackProvider: .deepgram
            )
        }
        return settings
    }

    private func saveSettings() {
        let settings = SavedSettings(
            provider: preferredProvider,
            accent: accentRegion,
            cloudFallback: cloudFallbackEnabled,
            fallbackProvider: fallbackProvider
        )

        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}

// MARK: - Provider Availability

extension TranscriptionRouter {
    /// Check if a specific provider is currently available
    func isProviderAvailable(_ provider: TranscriptionProvider) -> Bool {
        switch provider {
        case .onDevice:
            return onDeviceEngine.isAvailable
        case .deepgram, .assemblyai:
            return true // Cloud always "available" (actual availability checked at request time)
        case .smart:
            return onDeviceEngine.isAvailable // At minimum needs on-device
        }
    }

    /// Get recommended provider based on device capabilities
    var recommendedProvider: TranscriptionProvider {
        if onDeviceEngine.supportsOnDeviceRecognition {
            return .smart
        } else {
            return .deepgram
        }
    }
}
