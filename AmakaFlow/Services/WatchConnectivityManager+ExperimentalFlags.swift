//
//  WatchConnectivityManager+ExperimentalFlags.swift
//  AmakaFlow
//
//  AMA-2420 — push Experimental Strength auto-capture flag to the Watch.
//

import Foundation
import WatchConnectivity

extension WatchConnectivityManager {
    func syncExperimentalFlagsToWatch() {
        guard let session = session else { return }
        let payload: [String: Any] = [
            "action": "experimentalFlags",
            "strengthAutoCapture": StrengthAutoCaptureSettings.isEnabled
        ]
        // transferUserInfo survives when the Watch is not reachable.
        _ = session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("⌚️ Failed to send experimentalFlags: \(error)")
            }
        }
    }
}
