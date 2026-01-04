//
//  AmakaFlowCompanionApp.swift
//  AmakaFlowCompanion
//
//  Main app entry point for AmakaFlow Companion iOS app
//

import SwiftUI
import Sentry

@main
struct AmakaFlowCompanionApp: App {
    @ObservedObject private var pairingService = PairingService.shared
    @StateObject private var workoutsViewModel = WorkoutsViewModel()
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared
    @StateObject private var garminConnectivity = GarminConnectManager.shared

    init() {
        // Note: E2E test auth bypass (AMA-232) is handled in PairingService.init()
        // to ensure isPaired is set before SwiftUI evaluates the body

        // Initialize Sentry error tracking (AMA-225)
        SentrySDK.start { options in
            options.dsn = "https://7fa7415e248b5a064d84f74679719797@o951666.ingest.us.sentry.io/4510638875017216"

            // Adds IP for users
            options.sendDefaultPii = true

            // Performance monitoring (reduce in production)
            options.tracesSampleRate = 1.0

            // Profiling
            options.configureProfiling = {
                $0.sessionSampleRate = 1.0
                $0.lifecycle = .trace
            }

            // Screenshots and view hierarchy for debugging
            options.attachScreenshot = true
            options.attachViewHierarchy = true

            // Enable experimental logging
            options.experimental.enableLogs = true
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if pairingService.isPaired {
                    ContentView()
                        .environmentObject(workoutsViewModel)
                        .environmentObject(watchConnectivity)
                        .environmentObject(garminConnectivity)
                        .environmentObject(pairingService)
                        .task {
                            // Load workouts from API
                            await workoutsViewModel.loadWorkouts()

                            // Initialize WatchConnectivity asynchronously (non-blocking)
                            watchConnectivity.activate()

                            // Auto-reconnect to saved Garmin device if available
                            if garminConnectivity.savedDeviceInfo != nil && !garminConnectivity.isConnected {
                                garminConnectivity.connectToSavedDevice()
                            }
                        }
                        .refreshable {
                            await workoutsViewModel.refreshWorkouts()
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
                } else {
                    PairingView()
                        .environmentObject(pairingService)
                }
            }
            .preferredColorScheme(.dark) // Force dark mode
        }
    }
}
