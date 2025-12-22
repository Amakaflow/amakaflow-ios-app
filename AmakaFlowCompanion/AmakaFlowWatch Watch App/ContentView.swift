//
//  ContentView.swift
//  AmakaFlowWatch Watch App
//
//  Main content view that switches between workout list and remote control
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager
    @ObservedObject var bridge = WatchConnectivityBridge.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            // Tab 1: Remote Control
            NavigationStack {
                WatchRemoteView(bridge: bridge)
                    .navigationTitle("Remote")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tag(0)

            // Tab 2: Workout List
            WorkoutListView()
                .tag(1)
        }
        .tabViewStyle(.verticalPage)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Request fresh state when app becomes active
                bridge.requestCurrentState()
            }
        }
        .onAppear {
            // Request state when view first appears
            bridge.requestCurrentState()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchWorkoutManager())
}
