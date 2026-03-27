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
    @State private var showSyncDashboard = false

    enum Tab: String, CaseIterable {
        case home = "Home"
        case workouts = "Workouts"
        case sources = "Sources"
        case calendar = "Calendar"
        case coach = "Coach"
        case history = "History"
        case social = "Social"
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
            case .coach:
                return "bubble.left.and.bubble.right.fill"
            case .history:
                return "clock.fill"
            case .social:
                return "person.2.fill"
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

            CoachChatView()
                .tabItem {
                    Image(systemName: Tab.coach.icon)
                    Text(Tab.coach.rawValue)
                }
                .tag(Tab.coach)
                .accessibilityIdentifier("coach_tab")

            ActivityHistoryView()
                .tabItem {
                    Image(systemName: Tab.history.icon)
                    Text(Tab.history.rawValue)
                }
                .tag(Tab.history)
                .accessibilityIdentifier("history_tab")


            FeedView()
                .tabItem {
                    Image(systemName: Tab.social.icon)
                    Text(Tab.social.rawValue)
                }
                .tag(Tab.social)
                .accessibilityIdentifier("social_tab")
            SettingsView(navigateToSyncDashboard: $showSyncDashboard)
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
        .fullScreenCover(isPresented: $showingWorkoutPlayer) {
            WorkoutPlayerView()
        }
        // Deep link notification handlers (AMA-1133)
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToCalendar)) { _ in
            selectedTab = .calendar
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToCoach)) { _ in
            selectedTab = .coach
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToWorkout)) { _ in
            selectedTab = .workouts
            // Show player if workout is running
            if WorkoutEngine.shared.phase == .running || WorkoutEngine.shared.phase == .paused {
                showingWorkoutPlayer = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToSync)) { _ in
            selectedTab = .settings
            showSyncDashboard = true
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutsViewModel())
        .environmentObject(WatchConnectivityManager.shared)
}
