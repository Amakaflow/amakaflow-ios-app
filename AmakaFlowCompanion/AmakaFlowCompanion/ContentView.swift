//
//  ContentView.swift
//  AmakaFlowCompanion
//
//  Main content view for AmakaFlow Companion iOS app
//

import SwiftUI

/// Top-level chrome destinations for the AMA-1992 six-tab navigation.
enum AFTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case workouts = "Workouts"
    case coach = "Coach"
    case library = "Library"
    case history = "History"
    case profile = "Profile"

    var id: Self { self }

    var title: String { rawValue }

    var activeIcon: String {
        switch self {
        case .home: return "house.fill"
        case .workouts: return "square.grid.2x2.fill"
        case .coach: return "bubble.left.and.text.bubble.fill"
        case .library: return "bookmark.fill"
        case .history: return "clock.arrow.circlepath"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .home: return "house"
        case .workouts: return "square.grid.2x2"
        case .coach: return "bubble.left.and.text.bubble"
        case .library: return "bookmark"
        case .history: return "clock.arrow.circlepath"
        case .profile: return "person.crop.circle"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .home: return "home_tab"
        case .workouts: return "workouts_tab"
        case .coach: return "coach_tab"
        case .library: return "library_tab"
        case .history: return "history_tab"
        case .profile: return "profile_tab"
        }
    }

    var rootAccessibilityIdentifier: String {
        switch self {
        case .home: return "home_screen"
        case .workouts: return "workouts_screen"
        case .coach: return "coach_screen"
        case .library: return "library_screen"
        case .history: return "history_screen"
        case .profile: return "profile_screen"
        }
    }

    static func destination(forDeepLink name: Notification.Name) -> AFTab? {
        switch name {
        case .deepLinkToCoach:
            return .coach
        case .deepLinkToWorkout:
            return .workouts
        case .deepLinkToCalendar:
            // Calendar is no longer top-level chrome; route to the closest
            // planning surface so the deep link lands on a real tab.
            return .workouts
        case .deepLinkToSync, .deepLinkToNutrition:
            return .profile
        default:
            return nil
        }
    }
}

enum AFTabSelectionAction: Equatable {
    case switchTo(AFTab)
    case popToRoot(AFTab)
}

struct AFTabSelectionState: Equatable {
    private(set) var selectedTab: AFTab
    private var resetCounts: [AFTab: Int]

    init(selectedTab: AFTab = .home) {
        self.selectedTab = selectedTab
        self.resetCounts = Dictionary(uniqueKeysWithValues: AFTab.allCases.map { ($0, 0) })
    }

    mutating func select(_ tab: AFTab) -> AFTabSelectionAction {
        guard tab != selectedTab else {
            resetCounts[tab, default: 0] += 1
            return .popToRoot(tab)
        }

        selectedTab = tab
        return .switchTo(tab)
    }

    mutating func route(to tab: AFTab) {
        selectedTab = tab
    }

    func resetCount(for tab: AFTab) -> Int {
        resetCounts[tab, default: 0]
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @State private var tabState = AFTabSelectionState(selectedTab: .home)
    @State private var showingWorkoutPlayer = false
    @State private var showSyncDashboard = false
    @State private var profilePath = NavigationPath()
    @State private var resetTokens: [AFTab: UUID] = Dictionary(
        uniqueKeysWithValues: AFTab.allCases.map { ($0, UUID()) }
    )

    private var selectedTab: AFTab { tabState.selectedTab }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            activeDestination
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AFTabBar(selectedTab: selectedTab, onSelect: selectTab)
        }
        .tint(Theme.Colors.readyHigh)
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
        // Deep link notification handlers (AMA-1133, AMA-1640)
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToCalendar)) { note in
            routeDeepLink(.deepLinkToCalendar)
            if let date = note.userInfo?["date"] as? String {
                viewModel.preselectCalendarDate(date)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToCoach)) { note in
            routeDeepLink(.deepLinkToCoach)
            if let threadId = note.userInfo?["threadId"] as? String {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .openCoachThread,
                        object: nil,
                        userInfo: ["threadId": threadId]
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToWorkout)) { note in
            routeDeepLink(.deepLinkToWorkout)
            if let workoutId = note.userInfo?["workoutId"] as? String {
                viewModel.selectWorkout(byId: workoutId)
            }
            if WorkoutEngine.shared.phase == .running || WorkoutEngine.shared.phase == .paused {
                showingWorkoutPlayer = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToSync)) { _ in
            routeDeepLink(.deepLinkToSync)
            showSyncDashboard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToNutrition)) { _ in
            routeDeepLink(.deepLinkToNutrition)
        }
    }

    @ViewBuilder
    private var activeDestination: some View {
        switch selectedTab {
        case .home:
            tabRoot(.home) {
                HomeView()
            }
        case .workouts:
            tabRoot(.workouts) {
                WorkoutsView()
            }
        case .coach:
            tabRoot(.coach) {
                CoachChatView()
            }
        case .library:
            tabRoot(.library) {
                KnowledgeLibraryView()
            }
        case .history:
            tabRoot(.history) {
                // AMA-1992: top-level History must show real completed
                // workouts. `HistoryView` is still sample-backed design work;
                // keep it out of primary chrome until AMA-200x rebuilds it
                // against production data.
                ActivityHistoryView()
            }
        case .profile:
            tabRoot(.profile) {
                NavigationStack(path: $profilePath) {
                    SettingsView(navigateToSyncDashboard: $showSyncDashboard)
                }
            }
        }
    }

    private func selectTab(_ tab: AFTab) {
        let action = tabState.select(tab)
        if case let .popToRoot(tab) = action {
            popToRoot(tab)
        }
    }

    private func routeDeepLink(_ name: Notification.Name) {
        guard let tab = AFTab.destination(forDeepLink: name) else { return }
        tabState.route(to: tab)
    }

    private func popToRoot(_ tab: AFTab) {
        if tab == .profile {
            profilePath = NavigationPath()
            showSyncDashboard = false
        }
        resetTokens[tab] = UUID()
    }

    private func resetToken(for tab: AFTab) -> UUID {
        resetTokens[tab] ?? UUID()
    }

    private func tabRoot<Content: View>(
        _ tab: AFTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .id(resetToken(for: tab))
            .overlay(alignment: .top) {
                // Invisible root marker for XCUITest/Maestro. Some SwiftUI
                // containers do not expose identifiers reliably on iOS 26.
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier(tab.rootAccessibilityIdentifier)
            }
    }
}

struct AFTabBar: View {
    let selectedTab: AFTab
    let onSelect: (AFTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.borderLight)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(AFTab.allCases) { tab in
                    AFTabBarButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        onSelect: onSelect
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.sm)
        }
        .background(
            Theme.Colors.surface
                .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityIdentifier("af_tabbar")
        .accessibilityElement(children: .contain)
    }
}

private struct AFTabBarButton: View {
    let tab: AFTab
    let isSelected: Bool
    let onSelect: (AFTab) -> Void

    var body: some View {
        Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Theme.Colors.readyHigh.opacity(0.30))
                            .frame(width: 46, height: 30)
                    }

                    ZStack(alignment: .topTrailing) {
                        Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .medium))

                        if tab == .coach, isSelected {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7, weight: .bold))
                                .offset(x: 8, y: -7)
                        }
                    }
                    .foregroundColor(isSelected ? Theme.Colors.readyHigh : Theme.Colors.textTertiary)
                }
                .frame(height: 32)

                Text(tab.title)
                    .font(Theme.Typography.label)
                    .foregroundColor(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutsViewModel())
        .environmentObject(WatchConnectivityManager.shared)
}

#Preview("AFTabBar · Light") {
    AFTabBar(selectedTab: .home) { _ in }
        .background(Theme.Colors.background)
        .environment(\.colorScheme, .light)
}

#Preview("AFTabBar · Dark") {
    AFTabBar(selectedTab: .coach) { _ in }
        .background(Theme.Colors.background)
        .environment(\.colorScheme, .dark)
}
