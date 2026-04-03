//
//  AmakaFlowApp.swift
//  AmakaFlow Companion
//
//  Main app entry point for AmakaFlow Companion iOS app
//

import SwiftUI

// @main - Removed: Using AmakaFlowCompanionApp.swift as the main entry point
struct AmakaFlowApp: App {
    @StateObject private var workoutsViewModel = WorkoutsViewModel()
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutsViewModel)
                .environmentObject(watchConnectivity)
                .preferredColorScheme(.dark) // Force dark mode
                .onAppear {
                    // Skip Apple Watch connectivity during E2E tests
                    let isUITestMode = ProcessInfo.processInfo.environment["UITEST_MODE"] == "true"
                    if !isUITestMode {
                        watchConnectivity.activate()
                    }
                }
        }
    }
}
