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
        case calendar = "Calendar"
        case social = "Social"
        case more = "More"

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .workouts: return "figure.run"
            case .calendar: return "calendar"
            case .social: return "person.2.fill"
            case .more: return "ellipsis.circle.fill"
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

            // AMA-1588: Calendar + Social tabs are non-MVP.
            // Hidden until FeatureFlags.nonMvp is enabled. Code stays in
            // the app so we can re-enable once the willingness-to-pay test
            // resolves.
            if FeatureFlags.nonMvp {
                CalendarView(onAddWorkout: {
                        selectedTab = .workouts
                    })
                    .tabItem {
                        Image(systemName: Tab.calendar.icon)
                        Text(Tab.calendar.rawValue)
                    }
                    .tag(Tab.calendar)
                    .accessibilityIdentifier("calendar_tab")

                FeedView()
                    .tabItem {
                        Image(systemName: Tab.social.icon)
                        Text(Tab.social.rawValue)
                    }
                    .tag(Tab.social)
                    .accessibilityIdentifier("social_tab")
            }

            MoreView(navigateToSyncDashboard: $showSyncDashboard)
                .tabItem {
                    Image(systemName: Tab.more.icon)
                    Text(Tab.more.rawValue)
                }
                .tag(Tab.more)
                .accessibilityIdentifier("more_tab")
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
            // AMA-1588: Calendar tab is hidden in MVP. If a deep-link fires
            // while the tab is gated off, fall back to Workouts (closest
            // adjacent surface) so the user doesn't land on a non-existent
            // tab state.
            selectedTab = FeatureFlags.nonMvp ? .calendar : .workouts
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToCoach)) { _ in
            selectedTab = .more
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToWorkout)) { _ in
            selectedTab = .workouts
            // Show player if workout is running
            if WorkoutEngine.shared.phase == .running || WorkoutEngine.shared.phase == .paused {
                showingWorkoutPlayer = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToSync)) { _ in
            selectedTab = .more
            showSyncDashboard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToNutrition)) { _ in
            selectedTab = .more
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutsViewModel())
        .environmentObject(WatchConnectivityManager.shared)
}
