// GarminCIQAppIdentity.swift
// AMA-2342 — single source of truth for Connect IQ app / store UUIDs.
// Must match amakaflow-garmin-ciq/manifest.xml application id.

import Foundation

enum GarminCIQAppIdentity {
    /// Sideloaded / Store Connect IQ application id (amakaflow-garmin-ciq manifest).
    static let appUUID: UUID = {
        guard let uuid = UUID(uuidString: "d79bef4b-8805-44f2-8cdb-9b784a3be996") else {
            preconditionFailure("Invalid Garmin CIQ app UUID")
        }
        return uuid
    }()

    /// Connect IQ Store listing id (same until Store publish diverges).
    static let storeUUID = appUUID
}
