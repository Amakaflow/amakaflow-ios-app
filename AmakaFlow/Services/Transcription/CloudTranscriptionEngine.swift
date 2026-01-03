//
//  CloudTranscriptionEngine.swift
//  AmakaFlow
//
//  Cloud-based transcription via backend API (AMA-229)
//  Supports Deepgram and AssemblyAI providers
//

import Foundation

/// Cloud transcription engine that calls backend API
/// Backend proxies to Deepgram or AssemblyAI for actual transcription
/// Advantages: Better accuracy for accents, vocabulary boosting, handles noisy audio
/// Limitations: Requires network, small cost per minute
final class CloudTranscriptionEngine: TranscriptionEngine {
    // MARK: - TranscriptionEngine Protocol

    var providerName: String { provider.rawValue }

    var isAvailable: Bool {
        // Cloud is available if we have network connectivity
        // Could add more sophisticated network reachability check here
        true
    }

    // MARK: - Properties

    private let provider: TranscriptionProvider
    private let apiService: APIService
    private var currentTask: Task<TranscriptionResult, Error>?

    // MARK: - Initialization

    init(provider: TranscriptionProvider, apiService: APIService = .shared) {
        precondition(provider == .deepgram || provider == .assemblyai,
                     "CloudTranscriptionEngine only supports deepgram or assemblyai providers")
        self.provider = provider
        self.apiService = apiService
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        language: String,
        keywords: [String]?
    ) async throws -> TranscriptionResult {
        // Read audio file data
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw TranscriptionError.invalidAudioFormat
        }

        // Create cancellable task
        let task = Task {
            try await performTranscription(
                audioData: audioData,
                language: language,
                keywords: keywords
            )
        }
        currentTask = task

        return try await task.value
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private Implementation

    private func performTranscription(
        audioData: Data,
        language: String,
        keywords: [String]?
    ) async throws -> TranscriptionResult {
        // Check for cancellation
        try Task.checkCancellation()

        // Call backend API
        let response = try await apiService.transcribeAudio(
            audioData: audioData.base64EncodedString(),
            provider: provider.rawValue,
            language: language,
            keywords: keywords ?? [],
            includeWordTimings: true
        )

        // Check for cancellation before processing response
        try Task.checkCancellation()

        // Map response to TranscriptionResult
        let wordTimings = response.words?.map { word in
            WordTiming(
                word: word.word,
                start: word.start,
                end: word.end,
                confidence: word.confidence
            )
        }

        return TranscriptionResult(
            text: response.text,
            confidence: response.confidence,
            words: wordTimings,
            provider: provider
        )
    }
}

// MARK: - Provider-Specific Configuration

extension CloudTranscriptionEngine {
    /// Deepgram-optimized settings for fitness vocabulary
    static func deepgram(apiService: APIService = .shared) -> CloudTranscriptionEngine {
        CloudTranscriptionEngine(provider: .deepgram, apiService: apiService)
    }

    /// AssemblyAI-optimized settings (budget option)
    static func assemblyAI(apiService: APIService = .shared) -> CloudTranscriptionEngine {
        CloudTranscriptionEngine(provider: .assemblyai, apiService: apiService)
    }
}
