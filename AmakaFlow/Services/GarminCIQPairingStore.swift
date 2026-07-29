//
//  GarminCIQPairingStore.swift
//  AmakaFlow
//
//  AMA-2342: Start → Garmin must gate on CIQ Devices pairing (mapper token),
//  not Garmin Connect Mobile BLE / savedDeviceInfo. GCM being linked does not
//  mean garmin_workout_queue fan-out has a device token.
//

import Combine
import Foundation

/// Cached CIQ wearable pairing for Start sheet + one-tap push.
@MainActor
final class GarminCIQPairingStore: ObservableObject {
    static let shared = GarminCIQPairingStore()

    private static let defaultsKey = "garmin_ciq_devices_paired"

    @Published private(set) var hasPairedGarmin: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasPairedGarmin = defaults.bool(forKey: Self.defaultsKey)
    }

    /// Update cache from a Devices list response (wearables only from BFF).
    func update(from devices: [Components.Schemas.PairedDevice]) {
        let paired = devices.contains { Self.isGarminWearable($0) }
        guard paired != hasPairedGarmin else {
            defaults.set(paired, forKey: Self.defaultsKey)
            return
        }
        hasPairedGarmin = paired
        defaults.set(paired, forKey: Self.defaultsKey)
    }

    /// Best-effort refresh — keeps last cache on network failure.
    func refresh(apiService: APIServiceProviding? = nil) async {
        let api = apiService ?? AppDependencies.current.apiService
        do {
            let devices = try await api.listDevices()
            update(from: devices)
        } catch {
            // Keep last-known pairing; Start sheet still recoverable via PAIR row.
        }
    }

    /// Mirrors DevicesViewModel wearable heuristic — BFF names CIQ rows "Garmin".
    static func isGarminWearable(_ device: Components.Schemas.PairedDevice) -> Bool {
        let haystack = "\(device.name) \(device.model ?? "")".lowercased()
        return haystack.contains("garmin")
            || haystack.contains("forerunner")
            || haystack.contains("fenix")
            || haystack.contains("epix")
            || haystack.contains("t-rex")
            || haystack.contains("trex")
    }
}
