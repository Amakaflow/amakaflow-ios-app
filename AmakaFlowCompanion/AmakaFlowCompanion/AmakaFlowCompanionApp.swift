//
//  AmakaFlowCompanionApp.swift
//  AmakaFlowCompanion
//
//  Main app entry point for AmakaFlow Companion iOS app
//

import SwiftUI

@main
struct AmakaFlowCompanionApp: App {
    @StateObject private var workoutsViewModel = WorkoutsViewModel()
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared
    @StateObject private var garminConnectivity = GarminConnectManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutsViewModel)
                .environmentObject(watchConnectivity)
                .environmentObject(garminConnectivity)
                .preferredColorScheme(.dark) // Force dark mode
                .task {
                    // Initialize WatchConnectivity asynchronously (non-blocking)
                    watchConnectivity.activate()

                    // Auto-reconnect to saved Garmin device if available
                    if garminConnectivity.savedDeviceInfo != nil && !garminConnectivity.isConnected {
                        garminConnectivity.connectToSavedDevice()
                    }
                }
                .onOpenURL { url in
                    // Handle Garmin Connect IQ callbacks
                    print("⌚ [APP] onOpenURL received: \(url.absoluteString)")
                    print("⌚ [APP] URL scheme: \(url.scheme ?? "nil")")
                    print("⌚ [APP] URL host: \(url.host ?? "nil")")
                    print("⌚ [APP] URL path: \(url.path)")
                    print("⌚ [APP] URL query: \(url.query ?? "nil")")
                    let handled = garminConnectivity.handleURL(url)
                    print("⌚ [APP] URL handled: \(handled)")
                }
        }
    }
}
