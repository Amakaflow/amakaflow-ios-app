//
//  VoiceRecordingService.swift
//  AmakaFlow
//
//  Records user voice for workout transcription (AMA-5)
//

import Foundation
import AVFoundation
import Combine

/// Service for recording voice input for workout descriptions
@MainActor
class VoiceRecordingService: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var error: RecordingError?

    // MARK: - Properties

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTimer: Timer?
    private var durationTimer: Timer?
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }

    /// Maximum recording duration (5 minutes)
    let maxDuration: TimeInterval = 300

    // MARK: - Recording Settings

    /// Audio settings optimized for speech recognition
    private var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,  // 16kHz for speech recognition
            AVNumberOfChannelsKey: 1,   // Mono
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    // MARK: - Error Types

    enum RecordingError: LocalizedError {
        case permissionDenied
        case audioSessionFailed(Error)
        case recorderFailed(Error)
        case noRecording
        case recordingTooShort
        case recordingCancelled

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission is required"
            case .audioSessionFailed(let error):
                return "Audio setup failed: \(error.localizedDescription)"
            case .recorderFailed(let error):
                return "Recording failed: \(error.localizedDescription)"
            case .noRecording:
                return "No recording found"
            case .recordingTooShort:
                return "Recording too short. Please describe your workout."
            case .recordingCancelled:
                return "Recording was cancelled"
            }
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Recording Control

    /// Start recording voice input
    func startRecording() async throws -> URL {
        // Check permission
        guard PermissionManager.shared.hasMicrophonePermission else {
            throw RecordingError.permissionDenied
        }

        // Configure audio session for recording
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            throw RecordingError.audioSessionFailed(error)
        }

        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_workout_\(UUID().uuidString).wav"
        let url = tempDir.appendingPathComponent(fileName)
        recordingURL = url

        // Create and configure recorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
        } catch {
            throw RecordingError.recorderFailed(error)
        }

        // Start recording
        guard audioRecorder?.record() == true else {
            throw RecordingError.recorderFailed(NSError(domain: "VoiceRecording", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"]))
        }

        isRecording = true
        recordingDuration = 0
        error = nil

        // Start metering timer
        startMeteringTimer()

        // Start duration timer
        startDurationTimer()

        return url
    }

    /// Stop recording and return the audio file URL
    func stopRecording() async throws -> URL {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else {
            throw RecordingError.noRecording
        }

        // Stop timers
        stopTimers()

        // Stop recording
        recorder.stop()
        isRecording = false

        // Deactivate audio session
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        // Validate recording duration (minimum 1 second)
        if recordingDuration < 1.0 {
            cleanup()
            throw RecordingError.recordingTooShort
        }

        return url
    }

    /// Cancel current recording
    func cancelRecording() {
        stopTimers()

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        // Clean up temp file
        cleanup()

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        error = .recordingCancelled
    }

    // MARK: - Timer Management

    private func startMeteringTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAudioLevel()
            }
        }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.recordingDuration += 0.1

                // Auto-stop at max duration
                if self.recordingDuration >= self.maxDuration {
                    try? await self.stopRecording()
                }
            }
        }
    }

    private func stopTimers() {
        meterTimer?.invalidate()
        meterTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, isRecording else {
            audioLevel = 0
            return
        }

        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)

        // Convert decibels (-160 to 0) to normalized value (0 to 1)
        // -60dB is roughly ambient noise, 0dB is max
        let normalizedLevel = max(0, min(1, (decibels + 60) / 60))
        audioLevel = normalizedLevel
    }

    // MARK: - Cleanup

    private func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        audioRecorder = nil
    }

    /// Clean up any leftover temporary files
    func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in contents where file.lastPathComponent.hasPrefix("voice_workout_") {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            print("[VoiceRecording] Failed to clean temp files: \(error)")
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor in
            switch type {
            case .began:
                // Interruption started (e.g., phone call)
                if isRecording {
                    cancelRecording()
                }
            case .ended:
                // Interruption ended - user can restart if needed
                break
            @unknown default:
                break
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceRecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                error = .recorderFailed(NSError(domain: "VoiceRecording", code: -2, userInfo: [NSLocalizedDescriptionKey: "Recording finished unsuccessfully"]))
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.error = .recorderFailed(error)
            }
        }
    }
}
