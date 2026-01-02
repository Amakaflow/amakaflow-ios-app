//
//  PermissionManager.swift
//  AmakaFlow
//
//  Manages microphone and speech recognition permissions for voice workout creation (AMA-5)
//

import AVFoundation
import Combine
import Foundation
import Speech
import UIKit

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    // MARK: - Published Properties

    @Published private(set) var microphoneStatus: AVAudioSession.RecordPermission = .undetermined
    @Published private(set) var speechRecognitionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // MARK: - Computed Properties

    /// Whether microphone permission is granted
    var hasMicrophonePermission: Bool {
        microphoneStatus == .granted
    }

    /// Whether speech recognition permission is granted
    var hasSpeechRecognitionPermission: Bool {
        speechRecognitionStatus == .authorized
    }

    /// Whether all required permissions are granted
    var hasAllPermissions: Bool {
        hasMicrophonePermission && hasSpeechRecognitionPermission
    }

    /// Whether we can request permissions (not yet denied)
    var canRequestPermissions: Bool {
        microphoneStatus != .denied && speechRecognitionStatus != .denied
    }

    /// User-friendly message for permission status
    var permissionStatusMessage: String {
        if hasAllPermissions {
            return "Ready to record"
        }

        var missing: [String] = []
        if !hasMicrophonePermission {
            missing.append("microphone")
        }
        if !hasSpeechRecognitionPermission {
            missing.append("speech recognition")
        }

        if microphoneStatus == .denied || speechRecognitionStatus == .denied {
            return "Please enable \(missing.joined(separator: " and ")) in Settings"
        }

        return "Tap to enable \(missing.joined(separator: " and "))"
    }

    // MARK: - Initialization

    private init() {
        refreshPermissionStatus()
    }

    // MARK: - Permission Methods

    /// Refresh current permission status
    func refreshPermissionStatus() {
        microphoneStatus = AVAudioSession.sharedInstance().recordPermission
        speechRecognitionStatus = SFSpeechRecognizer.authorizationStatus()
    }

    /// Request all required permissions
    /// - Returns: True if all permissions were granted
    @discardableResult
    func requestPermissions() async -> Bool {
        // Request microphone permission
        let micGranted = await requestMicrophonePermission()

        // Request speech recognition permission
        let speechGranted = await requestSpeechRecognitionPermission()

        // Refresh status after requests
        refreshPermissionStatus()

        return micGranted && speechGranted
    }

    /// Request microphone permission only
    /// - Returns: True if permission was granted
    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in
                    self.microphoneStatus = granted ? .granted : .denied
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Request speech recognition permission only
    /// - Returns: True if permission was granted
    func requestSpeechRecognitionPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.speechRecognitionStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    /// Open system settings for the app
    func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
