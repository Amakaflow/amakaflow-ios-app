//
//  AudioCueManager.swift
//  AmakaFlow
//
//  Manages audio cues and text-to-speech for workout announcements
//

import Foundation
import AVFoundation
import Combine

class AudioCueManager: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }

    @Published var isSpeaking = false
    @Published var isEnabled = true

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        do {
            // Duck other audio (like music) while speaking
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func activateAudioSession() {
        do {
            try audioSession.setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - Speech

    func speak(_ text: String, priority: SpeechPriority = .normal) {
        guard isEnabled else { return }

        // Cancel any ongoing speech for high priority
        if priority == .high && synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        activateAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1 // Slightly faster
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Use different settings for countdown vs announcements
        switch priority {
        case .countdown:
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.3
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0
        case .high:
            utterance.preUtteranceDelay = 0.1
        case .normal:
            utterance.preUtteranceDelay = 0.2
        }

        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        deactivateAudioSession()
    }

    // MARK: - Workout Announcements

    func announceWorkoutStart(_ workoutName: String) {
        speak("Starting \(workoutName)", priority: .high)
    }

    func announceStep(_ stepName: String, roundInfo: String? = nil) {
        var announcement = stepName
        if let round = roundInfo {
            announcement = "\(round). \(stepName)"
        }
        speak(announcement, priority: .high)
    }

    func announceCountdown(_ seconds: Int) {
        speak("\(seconds)", priority: .countdown)
    }

    func announceWorkoutComplete() {
        speak("Workout complete. Great job!", priority: .high)
    }

    func announcePaused() {
        speak("Paused", priority: .normal)
    }

    func announceResumed() {
        speak("Resuming", priority: .normal)
    }
}

// MARK: - Speech Priority

enum SpeechPriority {
    case countdown  // Very fast, no delay
    case high       // Interrupts, minimal delay
    case normal     // Default behavior
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioCueManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
        deactivateAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
        deactivateAudioSession()
    }
}
