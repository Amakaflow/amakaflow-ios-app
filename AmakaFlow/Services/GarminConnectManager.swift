//
//  GarminConnectManager.swift
//  AmakaFlow
//
//  Manages communication between iPhone and Garmin watches via Connect IQ SDK
//
//  To enable ConnectIQ SDK:
//  1. Add ConnectIQ.framework to the project
//  2. Add -DCONNECTIQ_ENABLED to Other Swift Flags in Build Settings
//  3. Or use CocoaPods: pod 'ConnectIQ', '~> 1.0'
//

import Foundation
import Combine

#if CONNECTIQ_ENABLED
import ConnectIQ
#endif

// MARK: - Garmin Connect Manager

/// Manages Garmin watch connectivity via Garmin Connect Mobile SDK
/// Mirrors functionality of WatchConnectivityManager for Apple Watch
@MainActor
class GarminConnectManager: NSObject, ObservableObject {
    static let shared = GarminConnectManager()

    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var isAppInstalled = false
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var lastError: Error?
    @Published private(set) var knownDevices: [String] = []

    #if CONNECTIQ_ENABLED
    // MARK: - Connect IQ References
    private var connectIQ: ConnectIQ?
    private var connectedDevice: IQDevice?
    private var myApp: IQApp?
    private var availableDevices: [IQDevice] = []
    #endif

    /// AmakaFlow Connect IQ App UUID (must match manifest.xml in Garmin app)
    /// Generate a new UUID for production: https://www.uuidgenerator.net/
    private let appUUID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!

    /// Store UUID for the app in Connect IQ store (same as app UUID for now)
    private let storeUUID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!

    /// URL scheme for handling Garmin Connect IQ callbacks
    static let urlScheme = "amakaflow-ciq"

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    override init() {
        super.init()
        setupConnectIQ()
    }

    // MARK: - Setup

    private func setupConnectIQ() {
        #if CONNECTIQ_ENABLED
        connectIQ = ConnectIQ.sharedInstance()
        connectIQ?.initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: nil)
        print("⌚ GarminConnectManager initialized with ConnectIQ SDK")
        #else
        print("⌚ GarminConnectManager initialized (SDK not enabled - add CONNECTIQ_ENABLED flag)")
        #endif
    }

    // MARK: - Device Discovery

    /// Shows the Garmin device selection UI in Garmin Connect Mobile app
    /// User can select which Garmin watch to connect
    func showDeviceSelection() {
        #if CONNECTIQ_ENABLED
        connectIQ?.showDeviceSelection()
        print("⌚ Garmin device selection requested")
        #else
        print("⌚ Garmin SDK not enabled")
        #endif
    }

    /// Returns names of available Garmin devices
    func getKnownDeviceNames() -> [String] {
        return knownDevices
    }

    // MARK: - Send State to Watch

    /// Broadcasts workout state to connected Garmin watch
    /// - Parameter state: Current workout state from WorkoutEngine
    func sendWorkoutState(_ state: WorkoutState) {
        guard isConnected else {
            return
        }

        #if CONNECTIQ_ENABLED
        guard let app = myApp else {
            print("⌚ Garmin app not available")
            return
        }

        let message = buildStateMessage(from: state)

        connectIQ?.sendMessage(
            message,
            to: app,
            progress: nil,
            completion: { result in
                if result != .success {
                    print("⌚ Failed to send state to Garmin: \(result.rawValue)")
                    Task { @MainActor in
                        self.lastError = GarminConnectError.messageFailed
                    }
                }
            }
        )
        #endif
    }

    /// Sends acknowledgment to watch after processing command
    func sendAck(_ ack: CommandAck) {
        guard isConnected else { return }

        #if CONNECTIQ_ENABLED
        guard let app = myApp else { return }

        let message: [String: Any] = [
            "action": "commandAck",
            "commandId": ack.commandId,
            "status": ack.status.rawValue,
            "errorCode": ack.errorCode ?? ""
        ]

        connectIQ?.sendMessage(
            message,
            to: app,
            progress: nil,
            completion: { _ in }
        )
        #endif
    }

    // MARK: - Message Building

    private func buildStateMessage(from state: WorkoutState) -> [String: Any] {
        return [
            "action": "stateUpdate",
            "version": state.stateVersion,
            "workoutId": state.workoutId,
            "workoutName": state.workoutName,
            "phase": state.phase.rawValue,
            "stepIndex": state.stepIndex,
            "stepCount": state.stepCount,
            "stepName": state.stepName,
            "stepType": state.stepType.rawValue,
            "remainingMs": state.remainingMs ?? 0,
            "roundInfo": state.roundInfo ?? ""
        ]
    }

    // MARK: - Handle Messages from Watch

    /// Handles incoming messages from Garmin watch
    /// - Parameter message: Dictionary containing action and parameters
    func handleMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else {
            print("⌚ Garmin message missing action: \(message)")
            return
        }

        print("⌚ Received Garmin message: \(action)")

        switch action {
        case "command":
            handleCommandMessage(message)

        case "requestState":
            handleStateRequest()

        default:
            print("⌚ Unknown Garmin action: \(action)")
        }
    }

    private func handleCommandMessage(_ message: [String: Any]) {
        guard let commandString = message["command"] as? String,
              let commandId = message["commandId"] as? String else {
            print("⌚ Invalid command message from Garmin")
            return
        }

        Task { @MainActor in
            WorkoutEngine.shared.handleRemoteCommand(commandString, commandId: commandId)
        }
    }

    private func handleStateRequest() {
        Task { @MainActor in
            let engine = WorkoutEngine.shared
            if engine.isActive {
                engine.sendStateToGarmin()
            } else {
                // Send idle state
                let idleState = WorkoutState(
                    stateVersion: 0,
                    workoutId: "",
                    workoutName: "",
                    phase: .idle,
                    stepIndex: 0,
                    stepCount: 0,
                    stepName: "",
                    stepType: .reps,
                    remainingMs: nil,
                    roundInfo: nil,
                    lastCommandAck: nil
                )
                sendWorkoutState(idleState)
            }
        }
    }

    // MARK: - URL Handling

    /// Handle URL callbacks from Garmin Connect app
    /// Call this from AppDelegate/SceneDelegate's URL handling
    func handleURL(_ url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else { return false }

        #if CONNECTIQ_ENABLED
        // Parse devices returned from Garmin Connect Mobile's device picker
        if let devices = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice] {
            availableDevices = devices
            knownDevices = devices.map { $0.friendlyName ?? $0.uuid.uuidString }
            print("⌚ Received \(devices.count) Garmin devices from URL callback")

            // Automatically connect to first device
            if let firstDevice = devices.first {
                connectToDevice(firstDevice)
            }
            return true
        }
        #endif
        return false
    }

    // MARK: - Connection Management

    #if CONNECTIQ_ENABLED
    /// Connects to a specific IQDevice
    private func connectToDevice(_ device: IQDevice) {
        connectIQ?.register(forDeviceEvents: device, delegate: self)
        print("⌚ Registered for device events: \(device.friendlyName ?? device.uuid.uuidString)")
    }
    #endif

    /// Attempts to connect to a known Garmin device by name
    func connectToDevice(withName name: String) {
        #if CONNECTIQ_ENABLED
        guard let device = availableDevices.first(where: { $0.friendlyName == name }) else {
            print("⌚ Device not found: \(name)")
            return
        }

        connectToDevice(device)
        #endif
    }

    /// Disconnects from current Garmin device
    func disconnect() {
        #if CONNECTIQ_ENABLED
        if let device = connectedDevice {
            connectIQ?.unregister(forDeviceEvents: device, delegate: self)
        }
        if let app = myApp {
            connectIQ?.unregister(forAppMessages: app, delegate: self)
        }
        connectedDevice = nil
        myApp = nil
        #endif

        isConnected = false
        connectedDeviceName = nil
        print("⌚ Garmin disconnected")
    }
}

// MARK: - ConnectIQ Delegate Implementation

#if CONNECTIQ_ENABLED
extension GarminConnectManager: IQDeviceEventDelegate {

    nonisolated func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        Task { @MainActor in
            switch status {
            case .connected:
                self.connectedDevice = device
                self.connectedDeviceName = device.friendlyName ?? "Garmin Watch"
                self.isConnected = true
                self.registerForAppMessages(device)
                print("⌚ Garmin connected: \(self.connectedDeviceName ?? "Unknown")")

            case .notConnected, .bluetoothNotReady, .notFound, .invalidDevice:
                self.isConnected = false
                self.connectedDeviceName = nil
                self.connectedDevice = nil
                self.myApp = nil
                print("⌚ Garmin disconnected: \(status.rawValue)")

            @unknown default:
                print("⌚ Garmin unknown status: \(status.rawValue)")
            }
        }
    }

    private func registerForAppMessages(_ device: IQDevice) {
        myApp = IQApp(uuid: appUUID, store: storeUUID, device: device)

        connectIQ?.getAppStatus(myApp) { [weak self] appStatus in
            Task { @MainActor in
                guard let self = self else { return }

                let installed = appStatus?.isInstalled ?? false
                self.isAppInstalled = installed

                if installed, let app = self.myApp {
                    self.connectIQ?.register(forAppMessages: app, delegate: self)
                    print("⌚ Registered for Garmin app messages")
                } else {
                    print("⌚ AmakaFlow app not installed on Garmin watch")
                }
            }
        }
    }
}

extension GarminConnectManager: IQAppMessageDelegate {

    nonisolated func receivedMessage(_ message: Any!, from app: IQApp!) {
        if let dict = message as? [String: Any] {
            Task { @MainActor in
                self.handleMessage(dict)
            }
        }
    }
}
#endif

// MARK: - Errors

enum GarminConnectError: LocalizedError {
    case sdkNotIntegrated
    case deviceNotConnected
    case appNotInstalled
    case messageFailed
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .sdkNotIntegrated:
            return "Garmin Connect IQ SDK is not integrated. Add ConnectIQ framework and CONNECTIQ_ENABLED flag."
        case .deviceNotConnected:
            return "No Garmin watch is connected. Open Garmin Connect app and ensure your watch is paired."
        case .appNotInstalled:
            return "AmakaFlow app is not installed on your Garmin watch. Install it from the Connect IQ Store."
        case .messageFailed:
            return "Failed to send message to Garmin watch."
        case .invalidMessage:
            return "Received invalid message from Garmin watch."
        }
    }
}
