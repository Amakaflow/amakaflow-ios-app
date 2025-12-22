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
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchWorkoutManager())
}
