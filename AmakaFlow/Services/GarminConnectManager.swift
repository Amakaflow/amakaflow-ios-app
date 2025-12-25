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
import UIKit
import CoreBluetooth

#if CONNECTIQ_ENABLED
import ConnectIQ
#endif

// MARK: - Bluetooth Permission Kick
/// Forces iOS to request Bluetooth permission early so ConnectIQ SDK can access BT
final class BluetoothKick: NSObject, CBCentralManagerDelegate {
    private var mgr: CBCentralManager?
    var onStateChange: ((CBManagerState) -> Void)?

    func start() {
        mgr = CBCentralManager(delegate: self, queue: nil)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            print("⌚ [BT] CoreBluetooth state: \(central.state.rawValue)")
            self.onStateChange?(central.state)
        }
    }
}

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
    @Published private(set) var savedDeviceInfo: SavedDeviceInfo?
    @Published private(set) var lastDebugAction: String = "None"
    @Published private(set) var bluetoothState: CBManagerState = .unknown

    // MARK: - Bluetooth Kick
    private let bluetoothKick = BluetoothKick()

    // MARK: - Saved Device Info

    /// Persisted device information for reconnection without device picker
    struct SavedDeviceInfo: Codable {
        let uuid: String
        let modelName: String
        let friendlyName: String
    }

    private let savedDeviceKey = "GarminSavedDevice"

    #if CONNECTIQ_ENABLED
    // MARK: - Connect IQ References
    private var connectIQ: ConnectIQ?
    private var connectedDevice: IQDevice?
    private var myApp: IQApp?
    private var availableDevices: [IQDevice] = []
    #endif

    /// AmakaFlow Connect IQ App UUID (must match manifest.xml in Garmin app)
    /// This must match the id attribute in the Garmin watch app's manifest.xml
    private let appUUID = UUID(uuidString: "90ABF0DE-493E-47B7-B0A2-16A4D685D02A")!

    /// Store UUID for the app in Connect IQ store (same as app UUID)
    private let storeUUID = UUID(uuidString: "90ABF0DE-493E-47B7-B0A2-16A4D685D02A")!

    /// URL scheme for handling Garmin Connect IQ callbacks
    static let urlScheme = "amakaflow-ciq"

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    // Debug mode
    @Published var debugLog: [String] = []
    private let maxLogEntries = 50

    override init() {
        super.init()
        log("GarminConnectManager initializing...")

        // Start Bluetooth kick to trigger iOS permission prompt
        bluetoothKick.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.bluetoothState = state
                self?.log("[BT] State changed to: \(state.rawValue) (\(self?.btStateName(state) ?? "?"))")

                switch state {
                case .poweredOn:
                    // If BT becomes ready and we have saved device, try reconnecting
                    if let saved = self?.savedDeviceInfo, self?.isConnected == false {
                        self?.log("[BT] Powered on - attempting reconnect to saved device")
                        self?.connectToSavedDevice()
                    }

                case .unauthorized:
                    self?.log("❌ Bluetooth permission DENIED")
                    self?.log("Fix: Settings → Privacy & Security → Bluetooth → Enable AmakaFlowCompanion")
                    self?.lastDebugAction = "BT permission denied!"

                case .poweredOff:
                    self?.log("⚠️ Bluetooth is OFF - enable in Control Center or Settings")
                    self?.lastDebugAction = "BT is OFF"

                default:
                    break
                }
            }
        }
        bluetoothKick.start()

        setupConnectIQ()
        loadSavedDevice()
        setupNotifications()
        log("Init complete - SDK: \(connectIQAvailable ? "YES" : "NO")")
    }

    private func btStateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }

    /// Opens iOS Settings app (user can navigate to Bluetooth permissions)
    func openIOSSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Returns true if Bluetooth permission is denied
    var isBluetoothUnauthorized: Bool {
        bluetoothState == .unauthorized
    }

    private var connectIQAvailable: Bool {
        #if CONNECTIQ_ENABLED
        return true
        #else
        return false
        #endif
    }

    /// Add to debug log
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"
        print("⌚ \(entry)")

        Task { @MainActor in
            self.debugLog.insert(entry, at: 0)
            if self.debugLog.count > self.maxLogEntries {
                self.debugLog.removeLast()
            }
        }
    }

    /// Clear debug log
    func clearLog() {
        debugLog.removeAll()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("⌚ [DEBUG] App entering foreground")
                self?.lastDebugAction = "App foregrounded"
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("⌚ [DEBUG] App became active - checking for pending device selection")
                // Give a moment for any URL callbacks to process
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                if let self = self, self.availableDevices.isEmpty && self.lastDebugAction.contains("Reinit") {
                    print("⌚ [DEBUG] No devices yet after returning from GCM")
                }
            }
        }
    }

    // MARK: - Setup

    private func setupConnectIQ() {
        #if CONNECTIQ_ENABLED
        log("Setting up ConnectIQ SDK...")
        connectIQ = ConnectIQ.sharedInstance()
        log("ConnectIQ.sharedInstance() obtained: \(connectIQ != nil)")

        // Pass self as delegate to intercept "install GCM" prompts when GCM is actually installed
        connectIQ?.initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: self)
        log("SDK initialized with URL scheme: \(Self.urlScheme)")
        log("App UUID: \(appUUID.uuidString)")
        log("GCM installed: \(isGarminConnectInstalled())")
        #else
        log("SDK NOT enabled - add CONNECTIQ_ENABLED flag to build settings")
        #endif
    }

    // MARK: - Device Persistence

    /// Loads saved device from UserDefaults
    private func loadSavedDevice() {
        if let data = UserDefaults.standard.data(forKey: savedDeviceKey),
           let deviceInfo = try? JSONDecoder().decode(SavedDeviceInfo.self, from: data) {
            savedDeviceInfo = deviceInfo
            print("⌚ [DEBUG] Loaded saved device: \(deviceInfo.friendlyName) (\(deviceInfo.uuid))")
        }
    }

    /// Saves device info to UserDefaults for later reconnection
    private func saveDeviceInfo(uuid: String, modelName: String, friendlyName: String) {
        let deviceInfo = SavedDeviceInfo(uuid: uuid, modelName: modelName, friendlyName: friendlyName)
        if let data = try? JSONEncoder().encode(deviceInfo) {
            UserDefaults.standard.set(data, forKey: savedDeviceKey)
            savedDeviceInfo = deviceInfo
            print("⌚ [DEBUG] Saved device info: \(friendlyName) (\(uuid))")
        }
    }

    /// Clears saved device info
    func clearSavedDevice() {
        UserDefaults.standard.removeObject(forKey: savedDeviceKey)
        savedDeviceInfo = nil
        print("⌚ [DEBUG] Cleared saved device info")
    }

    /// Connects to a previously saved device (bypasses device picker)
    func connectToSavedDevice() {
        #if CONNECTIQ_ENABLED
        // Check if Bluetooth is ready first
        if bluetoothState != .poweredOn {
            log("⚠️ Bluetooth not ready (state: \(btStateName(bluetoothState))) - deferring reconnect")
            lastDebugAction = "BT not ready - waiting"
            return
        }

        guard let deviceInfo = savedDeviceInfo,
              let uuid = UUID(uuidString: deviceInfo.uuid) else {
            log("No saved device to connect to")
            return
        }

        log("Reconnecting to saved device: \(deviceInfo.friendlyName)")
        guard let device = IQDevice(id: uuid, modelName: deviceInfo.modelName, friendlyName: deviceInfo.friendlyName) else {
            log("Failed to create IQDevice from saved info")
            return
        }

        // Store device info but don't set isConnected yet
        availableDevices = [device]
        knownDevices = [deviceInfo.friendlyName]

        // Register for device events - this will trigger deviceStatusChanged callback
        log("Registering for device events...")
        ConnectIQ.sharedInstance()?.register(forDeviceEvents: device, delegate: self)

        // Check actual device status from SDK
        refreshConnectionState(for: device)
        lastDebugAction = "Checking device status..."
        #else
        log("SDK not enabled")
        #endif
    }

    #if CONNECTIQ_ENABLED
    /// Checks SDK device status and only sets connected state when truly connected
    private func refreshConnectionState(for device: IQDevice) {
        guard let ciq = connectIQ else {
            log("ERROR: connectIQ is nil")
            return
        }

        let status = ciq.getDeviceStatus(device)
        log("SDK getDeviceStatus = \(status.rawValue) (\(statusName(status)))")

        switch status {
        case .connected:
            log("✅ Device is CONNECTED")
            connectedDevice = device
            connectedDeviceName = device.friendlyName ?? "Garmin Watch"
            isConnected = true
            // Note: Don't call registerForAppMessages here - let deviceStatusChanged be the canonical path
            lastDebugAction = "Device connected"

        case .notConnected:
            log("⚠️ Device is NOT CONNECTED - waiting for connection")
            connectedDevice = device
            connectedDeviceName = device.friendlyName ?? "Garmin Watch"
            isConnected = false
            isAppInstalled = false
            lastDebugAction = "Device not connected"

        case .bluetoothNotReady:
            log("⚠️ Bluetooth NOT READY")
            isConnected = false
            lastDebugAction = "Bluetooth not ready"

        case .notFound:
            log("⚠️ Device NOT FOUND")
            isConnected = false
            lastDebugAction = "Device not found"

        case .invalidDevice:
            log("❌ INVALID DEVICE")
            isConnected = false
            lastDebugAction = "Invalid device"

        @unknown default:
            log("⚠️ Unknown status: \(status.rawValue)")
            isConnected = false
        }
    }

    private func statusName(_ status: IQDeviceStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .notConnected: return "notConnected"
        case .bluetoothNotReady: return "bluetoothNotReady"
        case .notFound: return "notFound"
        case .invalidDevice: return "invalidDevice"
        @unknown default: return "unknown"
        }
    }
    #endif

    /// Manually registers a device by UUID string
    /// - Parameters:
    ///   - uuidString: The device UUID (can be found in Garmin Connect app)
    ///   - friendlyName: Optional name for the device (defaults to "Garmin Watch")
    /// - Returns: true if registration was initiated
    @discardableResult
    func manuallyRegisterDevice(uuidString: String, friendlyName: String = "Garmin Watch") -> Bool {
        #if CONNECTIQ_ENABLED
        guard let uuid = UUID(uuidString: uuidString) else {
            print("⌚ [DEBUG] Invalid UUID format: \(uuidString)")
            lastError = GarminConnectError.invalidDeviceUUID
            return false
        }

        print("⌚ [DEBUG] Manually registering device with UUID: \(uuidString)")
        guard let device = IQDevice(id: uuid, modelName: "Garmin Watch", friendlyName: friendlyName) else {
            print("⌚ [DEBUG] Failed to create IQDevice")
            return false
        }

        // Save for future reconnection
        saveDeviceInfo(uuid: uuidString, modelName: "Garmin Watch", friendlyName: friendlyName)

        // Connect to the device
        connectToDevice(device)
        return true
        #else
        print("⌚ [DEBUG] SDK not enabled")
        return false
        #endif
    }

    // MARK: - Device Discovery

    /// Shows the Garmin device selection UI in Garmin Connect Mobile app
    /// User can select which Garmin watch to connect
    func showDeviceSelection() {
        log("showDeviceSelection() called")
        log("GCM installed: \(isGarminConnectInstalled())")
        log("iOS version: \(UIDevice.current.systemVersion)")
        log("Available devices: \(knownDevices.count)")

        #if CONNECTIQ_ENABLED
        // Use SDK's showDeviceSelection - this opens GCM's device picker
        // GCM will call back to our URL scheme with selected devices
        log("Calling ConnectIQ.shared.showDeviceSelection()...")
        lastDebugAction = "Opening GCM picker"
        ConnectIQ.sharedInstance()?.showDeviceSelection()
        log("showDeviceSelection() called - waiting for GCM callback via URL")
        #else
        lastDebugAction = "SDK not enabled"
        log("SDK not enabled")
        #endif
    }

    /// Opens GCM directly to device selection screen
    private func openGarminConnectForDeviceSelection() {
        // The Connect IQ SDK uses specific URL format for device selection
        // The callback must include the full scheme for GCM to recognize it

        // URL-encode the callback for safety
        let callbackEncoded = "\(Self.urlScheme)://".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.urlScheme

        // Try multiple URL formats - GCM versions handle these differently
        let urlsToTry = [
            // Full callback URL format with encoding (most reliable for newer GCM)
            "gcm-ciq://device-select?callback=\(callbackEncoded)",
            // Unencoded version (older GCM versions)
            "gcm-ciq://device-select?callback=\(Self.urlScheme)://",
            // Alternative parameter name
            "gcm-ciq://device-select?callbackUrlScheme=\(Self.urlScheme)",
            // Just the scheme name (simplest)
            "gcm-ciq://device-select?callback=\(Self.urlScheme)",
            // Connect IQ communication scheme (used internally by SDK)
            "ciq-comm://device-select?callback=\(callbackEncoded)",
        ]

        log("Callback URL scheme: \(Self.urlScheme)")
        log("Encoded callback: \(callbackEncoded)")

        for urlString in urlsToTry {
            guard let url = URL(string: urlString) else {
                log("Invalid URL: \(urlString)")
                continue
            }

            if UIApplication.shared.canOpenURL(url) {
                log("Opening GCM: \(urlString)")
                lastDebugAction = "Opening: \(url.scheme ?? "")://..."

                UIApplication.shared.open(url, options: [:]) { [weak self] success in
                    Task { @MainActor in
                        if success {
                            self?.log("GCM opened successfully - waiting for callback...")
                            self?.lastDebugAction = "GCM opened - select device"
                        } else {
                            self?.log("Failed to open: \(urlString)")
                            self?.lastDebugAction = "GCM open failed"
                        }
                    }
                }
                return
            } else {
                log("Cannot open URL (not registered?): \(urlString)")
            }
        }

        // Fallback: open GCM main app
        log("No device-select URL worked, trying main GCM app")
        lastDebugAction = "Opening GCM app"
        openGarminConnectApp()
    }

    /// Alternative: Shows device selection with our UI override delegate
    func showDeviceSelectionWithOverride() {
        #if CONNECTIQ_ENABLED
        print("⌚ [DEBUG] showDeviceSelectionWithOverride() called")
        lastDebugAction = "SDK+Override showDeviceSelection"
        connectIQ = ConnectIQ.sharedInstance()
        connectIQ?.initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: self)
        connectIQ?.showDeviceSelection()
        print("⌚ [DEBUG] Garmin device selection requested via SDK (with override)")
        #endif
    }

    /// Tries to discover devices - triggers device selection flow
    func discoverKnownDevices() {
        #if CONNECTIQ_ENABLED
        print("⌚ [DEBUG] discoverKnownDevices() called")
        print("⌚ [DEBUG] Currently have \(availableDevices.count) available devices")

        // If we already have devices, try to connect to first one
        if !availableDevices.isEmpty {
            print("⌚ [DEBUG] Reconnecting to first available device")
            if let firstDevice = availableDevices.first {
                connectToDevice(firstDevice)
            }
        } else {
            // No devices cached, need to go through device selection
            print("⌚ [DEBUG] No cached devices - triggering device selection")
            showDeviceSelection()
        }
        #else
        print("⌚ [DEBUG] SDK not enabled")
        #endif
    }

    /// Manually opens Garmin Connect Mobile app to device selection
    /// Use this as a fallback if showDeviceSelection() fails to detect the app
    func openGarminConnectApp() {
        // Try deep link to Connect IQ device selection with callback
        // Note: callback needs full scheme format for GCM to recognize it
        let callbackURL = "\(Self.urlScheme)://"
        let deepLinks = [
            "gcm-ciq://device-select?callback=\(callbackURL)",
            "gcm-ciq://device-select?callbackUrlScheme=\(Self.urlScheme)",
            "ciqstore://",
            "gcm-ciq://",
            "com-garmin-connect://",
            "garminconnect://"
        ]

        for deepLink in deepLinks {
            if let url = URL(string: deepLink),
               UIApplication.shared.canOpenURL(url) {
                print("⌚ [DEBUG] Attempting to open: \(deepLink)")
                lastDebugAction = "Trying: \(deepLink)"
                UIApplication.shared.open(url) { success in
                    Task { @MainActor in
                        if success {
                            self.lastDebugAction = "Opened OK: \(deepLink)"
                            print("⌚ [DEBUG] Successfully opened: \(deepLink)")
                        } else {
                            self.lastDebugAction = "Open FAILED: \(deepLink)"
                            print("⌚ [DEBUG] Failed to open: \(deepLink)")
                        }
                    }
                }
                return
            }
        }

        // If no URL scheme works, open App Store page for Garmin Connect
        print("⌚ [DEBUG] Could not open Garmin Connect, opening App Store")
        lastDebugAction = "No URL worked, opening App Store"
        if let appStoreURL = URL(string: "https://apps.apple.com/app/garmin-connect/id583446403") {
            UIApplication.shared.open(appStoreURL)
        }
    }

    /// Opens Garmin Connect IQ Store to the AmakaFlow app page
    func openConnectIQStore() {
        // Deep link to Connect IQ store app page
        let storeURL = "https://apps.garmin.com/apps/\(appUUID.uuidString.lowercased())"
        if let url = URL(string: storeURL) {
            print("⌚ [DEBUG] Opening Connect IQ Store: \(storeURL)")
            UIApplication.shared.open(url)
        }
    }

    /// Check if Garmin Connect Mobile is installed
    func isGarminConnectInstalled() -> Bool {
        let urlSchemes = ["gcm-ciq://", "com-garmin-connect://", "garminconnect://"]
        for scheme in urlSchemes {
            if let url = URL(string: scheme),
               UIApplication.shared.canOpenURL(url) {
                return true
            }
        }
        return false
    }

    /// Returns names of available Garmin devices
    func getKnownDeviceNames() -> [String] {
        return knownDevices
    }

    /// Returns SDK status for debugging
    func getSDKStatus() -> String {
        let gcInstalled = isGarminConnectInstalled() ? "YES" : "NO"
        #if CONNECTIQ_ENABLED
        let sdkEnabled = "YES"
        let sdkInitialized = connectIQ != nil ? "YES" : "NO"
        return "SDK: \(sdkEnabled), Init: \(sdkInitialized)\nGC App: \(gcInstalled)\nConnected: \(isConnected), CIQ App: \(isAppInstalled)\nDevices: \(knownDevices.count)\nLast: \(lastDebugAction)"
        #else
        return "SDK Enabled: NO\nGC App: \(gcInstalled)\n(CONNECTIQ_ENABLED flag not set)\nLast: \(lastDebugAction)"
        #endif
    }

    // MARK: - Simulator Support

    /// Connects to the Connect IQ Device Simulator running on a Mac
    /// The simulator must be running and accessible on the local network
    /// - Parameter host: The IP address or hostname of the Mac running the simulator (default: localhost for same machine)
    func connectToSimulator(host: String = "localhost", port: Int = 7381) {
        #if CONNECTIQ_ENABLED
        print("⌚ [DEBUG] Attempting to connect to Connect IQ Simulator at \(host):\(port)")
        lastDebugAction = "Connecting to simulator..."

        // The Connect IQ SDK has built-in simulator support
        // We need to tell it to use simulator mode instead of GCM
        if let ciq = connectIQ {
            // Create a simulated device for testing
            let simulatorUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            if let simulatedDevice = IQDevice(id: simulatorUUID, modelName: "Simulator", friendlyName: "CIQ Simulator") {
                print("⌚ [DEBUG] Created simulated device, registering for events...")
                lastDebugAction = "Registering simulator device"

                availableDevices = [simulatedDevice]
                knownDevices = ["CIQ Simulator"]
                connectToDevice(simulatedDevice)
            } else {
                print("⌚ [DEBUG] Failed to create simulated device")
                lastDebugAction = "Simulator device creation failed"
            }
        }
        #else
        print("⌚ [DEBUG] SDK not enabled, cannot connect to simulator")
        lastDebugAction = "SDK not enabled"
        #endif
    }

    /// Creates a mock device for UI testing without any Garmin hardware or simulator
    func connectToMockDevice() {
        #if CONNECTIQ_ENABLED
        print("⌚ [DEBUG] Creating mock device for testing")
        lastDebugAction = "Creating mock device..."

        let mockUUID = UUID()
        if let mockDevice = IQDevice(id: mockUUID, modelName: "Mock Watch", friendlyName: "Test Device") {
            availableDevices = [mockDevice]
            knownDevices = ["Test Device"]
            connectedDevice = mockDevice

            // Save for future use
            saveDeviceInfo(uuid: mockUUID.uuidString, modelName: "Mock Watch", friendlyName: "Test Device")

            // Mark as connected for UI testing
            isConnected = true
            isAppInstalled = true  // Simulate app installed for UI testing
            connectedDeviceName = "Test Device"

            // Create mock IQApp for message sending tests
            myApp = IQApp(uuid: appUUID, store: storeUUID, device: mockDevice)

            lastDebugAction = "Mock device connected"
            print("⌚ [DEBUG] Mock device connected: \(mockUUID)")
            print("⌚ [DEBUG] Mock app created with UUID: \(appUUID)")
        }
        #else
        // Even without SDK, we can fake connection for UI testing
        isConnected = true
        isAppInstalled = true
        connectedDeviceName = "Test Device (No SDK)"
        knownDevices = ["Test Device (No SDK)"]
        lastDebugAction = "Mock connected (no SDK)"
        print("⌚ [DEBUG] Mock device connected (SDK not enabled)")
        #endif
    }

    // MARK: - Send State to Watch

    /// Broadcasts workout state to connected Garmin watch
    /// - Parameter state: Current workout state from WorkoutEngine
    func sendWorkoutState(_ state: WorkoutState) {
        print("⌚ [DEBUG] sendWorkoutState called - isConnected: \(isConnected), phase: \(state.phase.rawValue)")

        guard isConnected else {
            print("⌚ [DEBUG] Not connected to Garmin, skipping send")
            return
        }

        #if CONNECTIQ_ENABLED
        guard let app = myApp else {
            print("⌚ [DEBUG] Garmin myApp is nil - app not registered")
            return
        }

        let message = buildStateMessage(from: state)
        print("⌚ [DEBUG] Sending message to Garmin: \(message)")

        connectIQ?.sendMessage(
            message,
            to: app,
            progress: nil,
            completion: { result in
                print("⌚ [DEBUG] Send result: \(result.rawValue)")
                if result != .success {
                    print("⌚ [DEBUG] Failed to send state to Garmin: \(result.rawValue)")
                    Task { @MainActor in
                        self.lastError = GarminConnectError.messageFailed
                    }
                } else {
                    print("⌚ [DEBUG] Successfully sent state to Garmin")
                }
            }
        )
        #else
        print("⌚ [DEBUG] CONNECTIQ_ENABLED not set, cannot send")
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
            "roundInfo": state.roundInfo ?? "",
            "targetReps": state.targetReps ?? 0
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

        log("Received Garmin message: \(action)")

        switch action {
        case "command":
            handleCommandMessage(message)

        case "requestState":
            handleStateRequest()

        case "pong":
            handlePongMessage(message)

        default:
            log("Unknown Garmin action: \(action)")
        }
    }

    private func handlePongMessage(_ message: [String: Any]) {
        let pingTimestamp = message["pingTimestamp"] as? Double ?? 0
        let pongTimestamp = message["pongTimestamp"] as? Int ?? 0
        log("===== PONG RECEIVED! =====")
        log("Ping timestamp: \(pingTimestamp)")
        log("Pong timestamp: \(pongTimestamp)")
        lastDebugAction = "Pong received!"

        // Now we know the app is truly reachable
        if !isAppInstalled {
            log("✅ First successful communication - marking app as installed")
            isAppInstalled = true
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
        log("========== URL RECEIVED ==========")
        log("Full URL: \(url.absoluteString)")
        log("Scheme: \(url.scheme ?? "nil") (expected: \(Self.urlScheme))")
        log("Host: \(url.host ?? "nil")")
        log("Path: \(url.path)")
        log("Query: \(url.query ?? "nil")")
        lastDebugAction = "URL: \(url.scheme ?? "nil")://\(url.host ?? "")"

        guard url.scheme == Self.urlScheme else {
            log("URL scheme mismatch - ignoring")
            lastDebugAction = "URL ignored (wrong scheme)"
            return false
        }
        log("URL scheme matches - processing...")

        #if CONNECTIQ_ENABLED
        log("Parsing device selection response via SDK...")
        lastDebugAction = "Parsing GCM response..."

        // Parse devices using SDK (as per Garmin documentation)
        guard let sdkDevices = ConnectIQ.sharedInstance()?.parseDeviceSelectionResponse(from: url) as? [IQDevice],
              !sdkDevices.isEmpty else {
            log("SDK parseDeviceSelectionResponse returned nil/empty")
            lastDebugAction = "No devices in response"
            return false
        }

        // Store devices
        availableDevices = sdkDevices
        knownDevices = sdkDevices.map { $0.friendlyName ?? $0.uuid.uuidString }
        log("Received \(sdkDevices.count) device(s) from GCM")
        lastDebugAction = "Got \(sdkDevices.count) device(s)"

        // Register for device events for ALL returned devices
        for device in sdkDevices {
            log("Registering for events: \(device.friendlyName ?? device.uuid.uuidString)")
            ConnectIQ.sharedInstance()?.register(forDeviceEvents: device, delegate: self)
        }

        // Auto-select first device
        if let firstDevice = sdkDevices.first {
            log("Auto-selecting: \(firstDevice.friendlyName ?? "device")")

            // Save for future reconnection
            saveDeviceInfo(
                uuid: firstDevice.uuid.uuidString,
                modelName: firstDevice.modelName ?? "Garmin Watch",
                friendlyName: firstDevice.friendlyName ?? "Garmin Watch"
            )

            // Check actual device status - only set connected if SDK confirms
            refreshConnectionState(for: firstDevice)
        }

        return true
        #else
        print("⌚ [DEBUG] CONNECTIQ_ENABLED not set, cannot parse URL")
        lastDebugAction = "SDK not enabled for URL"
        #endif
        return false
    }

    // MARK: - Connection Management

    #if CONNECTIQ_ENABLED
    /// Connects to a specific IQDevice
    private func connectToDevice(_ device: IQDevice) {
        print("⌚ [DEBUG] connectToDevice() called for: \(device.friendlyName ?? device.uuid.uuidString)")
        connectIQ?.register(forDeviceEvents: device, delegate: self)
        print("⌚ [DEBUG] Registered for device events - waiting for deviceStatusChanged callback...")
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
        print("⌚ [DEBUG] deviceStatusChanged called - status: \(status.rawValue)")
        Task { @MainActor in
            switch status {
            case .connected:
                print("⌚ [DEBUG] Device CONNECTED: \(device?.friendlyName ?? "Unknown")")
                self.connectedDevice = device
                self.connectedDeviceName = device?.friendlyName ?? "Garmin Watch"
                self.isConnected = true
                if let device = device {
                    // Save device info for future reconnection (bypasses broken picker)
                    self.saveDeviceInfo(
                        uuid: device.uuid.uuidString,
                        modelName: device.modelName ?? "Garmin Watch",
                        friendlyName: device.friendlyName ?? "Garmin Watch"
                    )
                    self.registerForAppMessages(device)
                }

            case .notConnected:
                print("⌚ [DEBUG] Device NOT CONNECTED")
                self.resetConnection()

            case .bluetoothNotReady:
                print("⌚ [DEBUG] Bluetooth NOT READY")
                self.resetConnection()

            case .notFound:
                print("⌚ [DEBUG] Device NOT FOUND")
                self.resetConnection()

            case .invalidDevice:
                print("⌚ [DEBUG] INVALID DEVICE")
                self.resetConnection()

            @unknown default:
                print("⌚ [DEBUG] Unknown status: \(status.rawValue)")
            }
        }
    }

    private func resetConnection() {
        isConnected = false
        connectedDeviceName = nil
        connectedDevice = nil
        myApp = nil
        isAppInstalled = false
    }

    private func registerForAppMessages(_ device: IQDevice) {
        log("registerForAppMessages called")
        log("App UUID: \(appUUID)")

        // Use store: nil as per Garmin SDK documentation
        myApp = IQApp(uuid: appUUID, store: nil, device: device)
        log("Created IQApp instance: \(myApp != nil)")

        guard let app = myApp else {
            log("ERROR: Failed to create IQApp")
            return
        }

        // Register for messages immediately - don't wait for getAppStatus
        // This is the pattern from Garmin's working examples
        connectIQ?.register(forAppMessages: app, delegate: self)
        log("Registered for app messages - waiting for first message to confirm app is reachable")
        // Note: Don't set isAppInstalled = true here - only after successful communication

        // Small delay before first message (common workaround per Garmin docs)
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 sec
            await MainActor.run {
                self.log("Ready to communicate with watch")
            }
        }
    }
}

extension GarminConnectManager: IQAppMessageDelegate {

    nonisolated func receivedMessage(_ message: Any!, from app: IQApp!) {
        Task { @MainActor in
            self.log("========== MESSAGE FROM WATCH ==========")
            self.log("App UUID: \(app?.uuid.uuidString ?? "nil")")
            self.log("Message type: \(type(of: message))")

            // Mark app as installed on first successful message
            if !self.isAppInstalled {
                self.log("✅ First message received - marking app as installed")
                self.isAppInstalled = true
            }

            if let dict = message as? [String: Any] {
                self.log("Message dict: \(dict)")
                self.handleMessage(dict)
            } else {
                self.log("WARNING: Message is not a dictionary: \(String(describing: message))")
            }
        }
    }
}

// MARK: - Debug Functions
extension GarminConnectManager {

    /// Sends a test ping message to the watch app
    func sendTestPing() {
        log("sendTestPing() called")
        log("isConnected: \(isConnected)")
        log("myApp: \(myApp != nil)")
        log("connectedDevice: \(connectedDevice != nil)")

        #if CONNECTIQ_ENABLED
        // Check device status first
        if let device = connectedDevice {
            let status = connectIQ?.getDeviceStatus(device) ?? .invalidDevice
            log("Device status: \(status.rawValue) (\(statusName(status)))")

            if status != .connected {
                log("⚠️ Device not connected - ping will likely fail")
                log("TIP: Try 'Wake' button first to open app on watch")
                lastDebugAction = "Device not connected"
            }
        }

        guard let app = myApp else {
            log("ERROR: myApp is nil - no app registered")
            log("TIP: Select device first via 'Discover' button")
            lastDebugAction = "No app - select device first"
            return
        }

        let message: [String: Any] = [
            "action": "ping",
            "timestamp": Date().timeIntervalSince1970
        ]

        log("Sending ping message: \(message)")
        lastDebugAction = "Sending test ping..."

        connectIQ?.sendMessage(
            message,
            to: app,
            progress: nil,
            completion: { [weak self] result in
                Task { @MainActor in
                    self?.log("Ping result: \(result.rawValue)")
                    switch result {
                    case .success:
                        self?.lastDebugAction = "Ping sent! Waiting for pong..."
                        self?.log("✅ Ping delivered to watch!")
                    default:
                        self?.lastDebugAction = "Ping failed: \(self?.sendResultName(result) ?? "?")"
                        self?.log("❌ Ping failed: \(self?.sendResultName(result) ?? "code \(result.rawValue)")")
                        self?.log("TIP: Make sure watch app is open, try 'Wake' button first")
                    }
                }
            }
        )
        #else
        log("SDK not enabled")
        lastDebugAction = "SDK not enabled"
        #endif
    }

    #if CONNECTIQ_ENABLED
    private func sendResultName(_ result: IQSendMessageResult) -> String {
        // From IQConstants.h - note the rawValues:
        // 0 = Success, 1 = Unknown, 2 = InternalError, 3 = DeviceNotAvailable
        // 4 = AppNotFound, 5 = DeviceIsBusy, 6 = UnsupportedType
        // 7 = InsufficientMemory, 8 = Timeout, 9 = MaxRetries
        // 10 = PromptNotDisplayed, 11 = AppAlreadyRunning
        switch result.rawValue {
        case 0: return "success"
        case 1: return "unknown error"
        case 2: return "internal error"
        case 3: return "device not available"  // This is what code 3 means!
        case 4: return "app not found"
        case 5: return "device busy"
        case 6: return "unsupported type"
        case 7: return "insufficient memory"
        case 8: return "timeout"
        case 9: return "max retries"
        case 10: return "prompt not displayed"
        case 11: return "app already running"
        default: return "code \(result.rawValue)"
        }
    }
    #endif

    /// Force re-initialization of the SDK
    func reinitializeSDK() {
        log("reinitializeSDK() called")
        #if CONNECTIQ_ENABLED
        connectIQ = nil
        connectedDevice = nil
        myApp = nil
        availableDevices = []
        isConnected = false
        isAppInstalled = false

        log("Cleared all state, reinitializing...")
        setupConnectIQ()
        lastDebugAction = "SDK reinitialized"
        #endif
    }

    /// Opens Connect IQ Store to install/update the watch app
    func openWatchApp() {
        log("openWatchApp() called")
        log("Opening Connect IQ Store for AmakaFlow...")
        log("App UUID: \(appUUID)")
        lastDebugAction = "Opening CIQ Store..."

        // Open the Connect IQ store page for this app
        // User can install/open from there
        let storeURL = "https://apps.garmin.com/apps/\(appUUID.uuidString.lowercased())"
        if let url = URL(string: storeURL) {
            log("Store URL: \(storeURL)")
            UIApplication.shared.open(url) { [weak self] success in
                Task { @MainActor in
                    if success {
                        self?.log("✅ Opened Connect IQ Store")
                        self?.lastDebugAction = "CIQ Store opened"
                    } else {
                        self?.log("❌ Failed to open store")
                        self?.lastDebugAction = "Store open failed"
                    }
                }
            }
        }
    }

    /// Sends an open app request to the watch - this may help wake up the app
    func sendOpenAppRequest() {
        log("sendOpenAppRequest() called")
        #if CONNECTIQ_ENABLED
        guard let app = myApp else {
            log("ERROR: myApp is nil - create app first")

            // Try to create app if we have a device
            if let device = connectedDevice {
                log("Creating IQApp for open request...")
                let appToOpen = IQApp(uuid: appUUID, store: nil, device: device)
                sendOpenRequest(for: appToOpen)
            } else {
                log("ERROR: No connected device")
                lastDebugAction = "No device for open request"
            }
            return
        }

        sendOpenRequest(for: app)
        #else
        log("SDK not enabled")
        #endif
    }

    #if CONNECTIQ_ENABLED
    private func sendOpenRequest(for app: IQApp?) {
        guard let app = app else { return }

        log("Sending openAppRequest for: \(app.uuid)")
        lastDebugAction = "Sending open app request..."

        connectIQ?.openAppRequest(app) { [weak self] result in
            Task { @MainActor in
                self?.log("openAppRequest result: \(result.rawValue)")
                switch result {
                case .success:
                    self?.log("✅ App open request sent successfully!")
                    self?.lastDebugAction = "App opened on watch!"
                    // Mark app as installed since openAppRequest succeeded
                    if self?.isAppInstalled == false {
                        self?.log("✅ openAppRequest succeeded - marking app as installed")
                        self?.isAppInstalled = true
                    }
                    // Now try sending a ping
                    self?.log("Waiting 1s then sending ping...")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self?.sendTestPing()
                default:
                    self?.log("❌ Open app request failed: \(result.rawValue)")
                    self?.lastDebugAction = "Open failed: code \(result.rawValue)"
                }
            }
        }
    }
    #endif

    /// Check if the app is actually installed on the watch via SDK
    /// Note: This often returns nil due to timing issues - use openWatchApp() instead
    func checkAppStatus() {
        log("checkAppStatus() called")
        log("NOTE: getAppStatus often returns nil - try 'Open' button instead")
        #if CONNECTIQ_ENABLED
        guard let device = connectedDevice else {
            log("ERROR: No connected device")
            lastDebugAction = "No device to check"
            return
        }

        // Create app reference for status check
        let appToCheck = IQApp(uuid: appUUID, store: nil, device: device)
        log("Checking app status on device: \(device.friendlyName ?? "Unknown")")
        log("App UUID: \(appUUID)")
        lastDebugAction = "Checking app status..."

        connectIQ?.getAppStatus(appToCheck) { [weak self] appStatus in
            Task { @MainActor in
                guard let self = self else { return }

                if let status = appStatus {
                    let installed = status.isInstalled
                    let version = status.version ?? 0
                    self.log("App status received:")
                    self.log("  - Installed: \(installed)")
                    self.log("  - Version: \(version)")
                    self.isAppInstalled = installed
                    self.lastDebugAction = installed ? "App installed (v\(version))" : "App NOT installed"
                } else {
                    self.log("getAppStatus returned nil (known timing issue)")
                    self.log("TIP: Try 'Open' button to launch app on watch")
                    self.lastDebugAction = "Status nil - try Open"
                }
            }
        }
        #else
        log("SDK not enabled")
        #endif
    }

    /// Try to discover devices - checks cached devices and triggers picker
    func tryAlternativeDeviceDiscovery() {
        log("tryAlternativeDeviceDiscovery() called")
        #if CONNECTIQ_ENABLED
        guard connectIQ != nil else {
            log("ERROR: connectIQ is nil")
            return
        }

        // Check if we have cached devices from previous picker
        if !availableDevices.isEmpty {
            log("Found \(availableDevices.count) cached device(s)")
            for device in availableDevices {
                log("  - \(device.friendlyName ?? "Unknown") UUID: \(device.uuid)")
            }
            if let first = availableDevices.first {
                log("Reconnecting to first cached device...")
                connectToDevice(first)
            }
            return
        }

        // Check saved device info
        if let saved = savedDeviceInfo {
            log("Found saved device: \(saved.friendlyName) UUID: \(saved.uuid)")
            log("Attempting to reconnect to saved device...")
            connectToSavedDevice()
            return
        }

        log("No cached or saved devices")
        log("Triggering device selection flow...")
        lastDebugAction = "Triggering picker..."
        showDeviceSelection()
        #else
        log("SDK not enabled")
        #endif
    }

    /// Returns detailed debug status
    func getDetailedStatus() -> [String: Any] {
        var status: [String: Any] = [
            "sdkEnabled": connectIQAvailable,
            "gcmInstalled": isGarminConnectInstalled(),
            "isConnected": isConnected,
            "isAppInstalled": isAppInstalled,
            "knownDevices": knownDevices,
            "connectedDeviceName": connectedDeviceName ?? "None",
            "lastAction": lastDebugAction,
            "appUUID": appUUID.uuidString
        ]

        #if CONNECTIQ_ENABLED
        status["connectIQInstance"] = connectIQ != nil
        status["myAppInstance"] = myApp != nil
        status["connectedDeviceInstance"] = connectedDevice != nil
        status["availableDevicesCount"] = availableDevices.count
        #endif

        return status
    }
}

extension GarminConnectManager: IQUIOverrideDelegate {

    /// Called when SDK thinks GCM needs to be installed
    /// We intercept this to check if GCM is actually installed and open it directly
    nonisolated func needsToInstallConnectMobile() {
        print("⌚ [DEBUG] SDK called needsToInstallConnectMobile()")
        Task { @MainActor in
            self.lastDebugAction = "SDK: needsToInstall callback"
            if self.isGarminConnectInstalled() {
                // GCM is installed but SDK doesn't detect it
                // Try the ciq-comm URL scheme which is specifically for Connect IQ communication
                print("⌚ [DEBUG] GCM is installed but SDK doesn't see it")
                print("⌚ [DEBUG] Trying ciq-comm URL scheme...")

                // ciq-comm is the internal scheme used by the SDK for device selection
                let ciqCommURL = "ciq-comm://device-select?callback=\(Self.urlScheme)"
                if let url = URL(string: ciqCommURL), UIApplication.shared.canOpenURL(url) {
                    print("⌚ [DEBUG] Opening via ciq-comm scheme")
                    self.lastDebugAction = "Trying ciq-comm://"
                    UIApplication.shared.open(url) { success in
                        Task { @MainActor in
                            self.lastDebugAction = success ? "ciq-comm opened OK" : "ciq-comm failed"
                        }
                    }
                } else {
                    // Fall back to gcm-ciq
                    print("⌚ [DEBUG] ciq-comm not available, falling back to gcm-ciq")
                    self.lastDebugAction = "Fallback to gcm-ciq"
                    self.openGarminConnectApp()
                }
            } else {
                // GCM really isn't installed - show App Store
                print("⌚ [DEBUG] GCM not installed, showing App Store")
                self.lastDebugAction = "GCM not installed"
                self.connectIQ?.showAppStoreForConnectMobile()
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
    case invalidDeviceUUID

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
        case .invalidDeviceUUID:
            return "Invalid device UUID format. UUID should be in format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
        }
    }
}
