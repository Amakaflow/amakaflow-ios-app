//
//  ContentView.swift
//  AmakaFlowCompanion
//
//  Main content view for AmakaFlow Companion iOS app
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @State private var selectedTab: Tab = .home
    @State private var showingWorkoutPlayer = false

    enum Tab: String, CaseIterable {
        case home = "Home"
        case workouts = "Workouts"
        case sources = "Sources"
        case calendar = "Calendar"
        case history = "History"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .home:
                return "house.fill"
            case .workouts:
                return "figure.run"
            case .sources:
                return "arrow.down.circle.fill"
            case .calendar:
                return "calendar"
            case .history:
                return "clock.fill"
            case .settings:
                return "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: Tab.home.icon)
                    Text(Tab.home.rawValue)
                }
                .tag(Tab.home)
                .accessibilityIdentifier("home_tab")

            WorkoutsView()
                .tabItem {
                    Image(systemName: Tab.workouts.icon)
                    Text(Tab.workouts.rawValue)
                }
                .tag(Tab.workouts)
                .accessibilityIdentifier("workouts_tab")

            SourcesView()
                .tabItem {
                    Image(systemName: Tab.sources.icon)
                    Text(Tab.sources.rawValue)
                }
                .tag(Tab.sources)
                .accessibilityIdentifier("sources_tab")

            CalendarView(onAddWorkout: {
                    selectedTab = .workouts
                })
                .tabItem {
                    Image(systemName: Tab.calendar.icon)
                    Text(Tab.calendar.rawValue)
                }
                .tag(Tab.calendar)
                .accessibilityIdentifier("calendar_tab")

            ActivityHistoryView()
                .tabItem {
                    Image(systemName: Tab.history.icon)
                    Text(Tab.history.rawValue)
                }
                .tag(Tab.history)
                .accessibilityIdentifier("history_tab")

            SettingsView()
                .tabItem {
                    Image(systemName: Tab.settings.icon)
                    Text(Tab.settings.rawValue)
                }
                .tag(Tab.settings)
                .accessibilityIdentifier("settings_tab")
        }
        .tint(Theme.Colors.accentBlue)
        .task {
            // Check for pending workouts on app open
            await viewModel.checkPendingWorkouts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPendingWorkouts)) { _ in
            Task {
                await viewModel.checkPendingWorkouts()
            }
        }
        .onOpenURL { url in
            // Handle deep link from Dynamic Island
            if url.scheme == "amakaflow" && url.host == "workout" {
                // Only show player if workout is running
                if WorkoutEngine.shared.phase == .running || WorkoutEngine.shared.phase == .paused {
                    showingWorkoutPlayer = true
                }
            }
        }
        .fullScreenCover(isPresented: $showingWorkoutPlayer) {
            WorkoutPlayerView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutsViewModel())
        .environmentObject(WatchConnectivityManager.shared)
}
