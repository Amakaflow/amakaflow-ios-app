//
//  WatchMainTabView.swift
//  AmakaFlowWatch Watch App
//
//  Main tab view integrating remote control, today's schedule, coach, and readiness (AMA-1150)
//

import SwiftUI

struct WatchMainTabView: View {
    @ObservedObject var bridge: WatchConnectivityBridge
    @ObservedObject var dayStateViewModel: DayStateViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: Workout Remote Control (existing)
            WatchRemoteView(bridge: bridge)
                .tag(0)

            // Tab 1: Today's Schedule (AMA-1150)
            TodayScheduleView(viewModel: dayStateViewModel)
                .tag(1)

            // Tab 2: Readiness Glance (AMA-1150)
            ReadinessGlanceView(viewModel: dayStateViewModel)
                .tag(2)

            // Tab 3: Quick Coach (AMA-1150)
            QuickCoachView(viewModel: dayStateViewModel)
                .tag(3)
        }
        .tabViewStyle(.verticalPage)
        // Show conflict alert as a sheet when detected
        .sheet(isPresented: conflictAlertBinding) {
            if let conflict = dayStateViewModel.activeConflict {
                ConflictAlertView(
                    conflict: conflict,
                    onAdjust: {
                        dayStateViewModel.handleConflictAdjust()
                    },
                    onKeep: {
                        dayStateViewModel.handleConflictKeep()
                    }
                )
            }
        }
    }

    private var conflictAlertBinding: Binding<Bool> {
        Binding(
            get: { dayStateViewModel.activeConflict != nil },
            set: { if !$0 { dayStateViewModel.dismissConflict() } }
        )
    }
}
