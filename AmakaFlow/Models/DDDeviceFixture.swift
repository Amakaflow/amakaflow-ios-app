//
//  DDDeviceFixture.swift
//  AmakaFlow
//
//  Static device-detail fixture matching `dd-device-dark.png` — no live watch API.
//

import Foundation

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

    static let sessionTypes: [(title: String, icon: String, key: String, defaultOn: Bool)] = [
        ("Hyrox / HIIT", "flame.fill", "Hyrox / HIIT", true),
        ("Runs", "figure.run", "Runs", false),
        ("Strength", "dumbbell.fill", "Strength", false),
        ("Everything else", "ellipsis.message.fill", "Everything else", false)
    ]
}
