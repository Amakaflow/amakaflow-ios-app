//
//  AudioProviding.swift
//  AmakaFlow
//
//  Protocol abstraction for audio cue playback to enable dependency injection and testing.
//

import Foundation

// Note: SpeechPriority enum is defined in AudioCueManager.swift

/// Protocol defining the audio cue interface for dependency injection
protocol AudioProviding {
    // MARK: - State

    /// Whether audio cues are currently enabled
    var isEnabled: Bool { get set }

    /// Whether the synthesizer is currently speaking
    var isSpeaking: Bool { get }

    // MARK: - Core Speech

    /// Speak text with specified priority
    func speak(_ text: String, priority: SpeechPriority)

    /// Stop any ongoing speech
    func stopSpeaking()

    // MARK: - Workout Announcements

    /// Announce workout start
    func announceWorkoutStart(_ workoutName: String)

    /// Announce current step with optional round info
    func announceStep(_ stepName: String, roundInfo: String?)

    /// Announce countdown number
    func announceCountdown(_ seconds: Int)

    /// Announce workout completion
    func announceWorkoutComplete()

    /// Announce paused state
    func announcePaused()

    /// Announce resumed state
    func announceResumed()

    /// Announce rest period
    func announceRest(isManual: Bool, seconds: Int)
}

// MARK: - Default Parameter Extensions

extension AudioProviding {
    /// Convenience method with default priority
    func speak(_ text: String) {
        speak(text, priority: .normal)
    }

    /// Convenience method with default roundInfo
    func announceStep(_ stepName: String) {
        announceStep(stepName, roundInfo: nil)
    }
}

// MARK: - AudioCueManager Conformance

extension AudioCueManager: AudioProviding {}
