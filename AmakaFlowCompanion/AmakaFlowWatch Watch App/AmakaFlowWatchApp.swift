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
    @StateObject private var connectivityBridge = WatchConnectivityBridge.shared
    @StateObject private var dayStateViewModel = DayStateViewModel()

    var body: some Scene {
        WindowGroup {
            WatchMainTabView(
                bridge: connectivityBridge,
                dayStateViewModel: dayStateViewModel
            )
            .environmentObject(workoutManager)
            .environmentObject(connectivityBridge)
            .onAppear {
                // Wire up the bridge to route phone push messages to watch state.
                connectivityBridge.dayStateViewModel = dayStateViewModel
                connectivityBridge.workoutManager = workoutManager
            }
        }
    }
}
