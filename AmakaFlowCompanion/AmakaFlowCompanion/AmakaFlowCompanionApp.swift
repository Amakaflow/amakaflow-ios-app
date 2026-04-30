//
//  AmakaFlowCompanionApp.swift
//  AmakaFlowCompanion
//
//  Main app entry point for AmakaFlow Companion iOS app
//

import SwiftUI
import Sentry
import ClerkKit

@main
struct AmakaFlowCompanionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel.shared
    @StateObject private var pairingService = PairingService.shared
    @StateObject private var workoutsViewModel: WorkoutsViewModel
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared
    @StateObject private var garminConnectivity = GarminConnectManager.shared
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var mentalModelGateRefresh = false

    init() {
        #if DEBUG
        // Unit tests: configure Clerk with a placeholder key so Clerk.shared doesn't
        // fatal-error when SwiftUI evaluates the body. Skip all other SDK init.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            Clerk.configure(publishableKey: "pk_test_ZXhhbXBsZS5jb20k")
            _workoutsViewModel = StateObject(wrappedValue: WorkoutsViewModel())
            return
        }
        #endif

        Clerk.configure(publishableKey: AppEnvironment.current.clerkPublishableKey)
        AuthViewModel.shared.start()

        // Wire up fixture dependencies when UITEST_USE_FIXTURES=true (AMA-544)
        #if DEBUG
        if UITestEnvironment.shared.useFixtures {
            _workoutsViewModel = StateObject(wrappedValue: WorkoutsViewModel(dependencies: .fixture))
            print("[AmakaFlowCompanionApp] Fixture mode: using FixtureAPIService")
        } else {
            _workoutsViewModel = StateObject(wrappedValue: WorkoutsViewModel())
        }

        if UITestEnvironment.shared.hasClerkTestUser {
            print("[AmakaFlowCompanionApp] UITEST Clerk test user configured")
            print("[AmakaFlowCompanionApp] useFixtures=\(UITestEnvironment.shared.useFixtures), skipOnboarding=\(UITestEnvironment.shared.skipOnboarding)")
        }
        #else
        _workoutsViewModel = StateObject(wrappedValue: WorkoutsViewModel())
        #endif

        // Initialize Sentry error tracking (AMA-225)
        SentrySDK.start { options in
            options.dsn = "https://7fa7415e248b5a064d84f74679719797@o951666.ingest.us.sentry.io/4510638875017216"

            // Adds IP for users
            options.sendDefaultPii = true

            // Performance monitoring (AMA-1083: reduced from 1.0 to 0.2 to limit quota usage)
            options.tracesSampleRate = 0.2

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

            // Session Replay (AMA-1084)
            // 10% of all sessions captured; 100% of sessions with errors/hangs.
            // sessionReplay is a top-level SentryOptions property (not under experimental) in sentry-cocoa 8.57+.
            // Auto-disabled on iOS 26+ / Liquid Glass masking issue — SDK handles this automatically.
            // Default masking: all text, images, and user input — no custom config needed.
            options.sessionReplay.sessionSampleRate = 0.1
            options.sessionReplay.onErrorSampleRate = 1.0

            // App hang tracking - detect when app freezes (AMA-971, AMA-1324)
            options.enableAppHangTracking = true
            #if targetEnvironment(simulator)
            // AMA-1324: Simulator XPC calls (e.g. Activity.request) are much slower
            // than on real devices, causing false-positive hang reports and SIGABRTs.
            options.appHangTimeoutInterval = 10.0
            #else
            options.appHangTimeoutInterval = 2.0
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !authViewModel.hasResolvedInitialSession {
                    // Wait for Clerk session hydration to avoid auth flash on startup
                    Color.black.ignoresSafeArea()
                } else if authViewModel.isAuthenticated {
                    ContentView()
                        .environmentObject(workoutsViewModel)
                        .environmentObject(watchConnectivity)
                        .environmentObject(garminConnectivity)
                        .environmentObject(pairingService)
                        .environmentObject(authViewModel)
                        .environmentObject(deepLinkManager)
                        .task {
                            // Wire up ViewModel for AppDelegate silent push handler (AMA-567)
                            appDelegate.workoutsViewModel = workoutsViewModel

                            // Load workouts from API
                            await workoutsViewModel.loadWorkouts()

                            // Initialize WatchConnectivity asynchronously (non-blocking)
                            // Skip when UITEST_SKIP_APPLE_WATCH=true to avoid system permission modal (AMA-549)
                            #if DEBUG
                            if !UITestEnvironment.shared.skipAppleWatch {
                                watchConnectivity.activate()
                            }
                            #else
                            watchConnectivity.activate()
                            #endif

                            // Auto-reconnect to saved Garmin device if available
                            if garminConnectivity.savedDeviceInfo != nil && !garminConnectivity.isConnected {
                                garminConnectivity.connectToSavedDevice()
                            }
                        }
                        .refreshable {
                            await workoutsViewModel.refreshWorkouts()
                        }
                        .onOpenURL { url in
                            // AMA-1259: Handle Universal Links and custom scheme deep links for import
                            if deepLinkManager.handleIncomingURL(url) {
                                return
                            }

                            // Handle Garmin Connect IQ callbacks (existing behavior)
                            print("[APP] onOpenURL received: \(url.absoluteString)")
                            let handled = garminConnectivity.handleURL(url)
                            print("[APP] URL handled by Garmin: \(handled)")

                            // Handle existing amakaflow://workout deep link (Dynamic Island)
                            if url.scheme == "amakaflow" && url.host == "workout" {
                                if WorkoutEngine.shared.phase == .running || WorkoutEngine.shared.phase == .paused {
                                    NotificationCenter.default.post(name: .deepLinkToWorkout, object: nil)
                                }
                            }
                        }
                        .sheet(isPresented: $deepLinkManager.showImportSheet) {
                            if let importURL = deepLinkManager.pendingImportURL {
                                DeepLinkImportView(urlString: importURL) {
                                    deepLinkManager.clearPendingImport()
                                    // Refresh workouts after import
                                    Task { await workoutsViewModel.refreshWorkouts() }
                                }
                            }
                        }
                } else {
                    unpairedRoot
                }
            }
            .environment(Clerk.shared)
            .environmentObject(authViewModel)
            .preferredColorScheme(.dark) // Force dark mode
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && authViewModel.isAuthenticated {
                    Task {
                        await workoutsViewModel.checkPendingWorkouts()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unpairedRoot: some View {
        let _ = mentalModelGateRefresh
        let userId = pairingService.userProfile?.id ?? UIDevice.current.identifierForVendor?.uuidString ?? "device"
        let seenKey = "mental_model_seen_\(userId)"

        if UserDefaults.standard.bool(forKey: seenKey) {
            PairingView()
                .environmentObject(pairingService)
                .onOpenURL { url in
                    // AMA-1259: Still handle deep links when not paired —
                    // store the URL so we can process it after pairing completes
                    _ = deepLinkManager.handleIncomingURL(url)
                }
        } else {
            MentalModelView(
                onContinue: { markMentalModelSeen(seenKey) },
                onSkip: { markMentalModelSeen(seenKey) }
            )
            .onOpenURL { url in
                _ = deepLinkManager.handleIncomingURL(url)
            }
        }
    }

    private func markMentalModelSeen(_ key: String) {
        UserDefaults.standard.set(true, forKey: key)
        mentalModelGateRefresh.toggle()
    }

}
