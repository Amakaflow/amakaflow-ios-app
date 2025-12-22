//
//  AmakaFlowWatchApp.swift
//  AmakaFlowWatch Watch App
//
//  Main entry point for AmakaFlowWatch Watch App
//

import SwiftUI

@main
struct AmakaFlowWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
        }
    }
}
