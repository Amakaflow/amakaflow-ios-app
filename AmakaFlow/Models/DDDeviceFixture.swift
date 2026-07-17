//
//  DDDeviceFixture.swift
//  AmakaFlow
//
//  Static device-detail fixture matching `dd-device-dark.png` — no live watch API.
//

import Foundation

struct DDDeviceSessionType {
    let title: String
    let icon: String
    let key: String
    let defaultOn: Bool
}

enum DDDeviceFixture {
    static let statusLine = "● CONNECTED · SYNCED 2M AGO"
    static let deviceName = "Amazfit T-Rex 3"
    static let batteryPercent = 78
    static let batteryCaption = "battery — enough for tonight"

    static let deliveredTitle = "Hyrox Sim — Stations 1–4"
    static let deliveredTime = "DELIVERED 6:14 PM"

    static let failedTitle = "DB Full-body AMRAP"
    static let failedReason =
        "Block 4 uses “open reps” — the follow-along needs a fixed count or time."

    static let sessionTypes: [DDDeviceSessionType] = [
        DDDeviceSessionType(title: "Hyrox / HIIT", icon: "flame.fill", key: "Hyrox / HIIT", defaultOn: true),
        DDDeviceSessionType(title: "Runs", icon: "figure.run", key: "Runs", defaultOn: false),
        DDDeviceSessionType(title: "Strength", icon: "dumbbell.fill", key: "Strength", defaultOn: false),
        DDDeviceSessionType(title: "Everything else", icon: "ellipsis.message.fill", key: "Everything else", defaultOn: false)
    ]
}
