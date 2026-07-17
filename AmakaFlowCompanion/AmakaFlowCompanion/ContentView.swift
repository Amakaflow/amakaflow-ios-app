//
//  ContentView.swift
//  AmakaFlowCompanion
//
//  Main content view for AmakaFlow Companion iOS app
//

import SwiftUI

/// Top-level chrome destinations for the AMA-2292 Daily Driver three-tab IA.
enum AFTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case library = "Library"
    case profile = "Profile"

    var id: Self { self }

    var title: String { rawValue }

    var activeIcon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .library: return "bookmark.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .today: return "sun.max"
        case .library: return "bookmark"
        case .profile: return "person.crop.circle"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .today: return "today_tab"
        case .library: return "library_tab"
        case .profile: return "profile_tab"
        }
    }

    var rootAccessibilityIdentifier: String {
        switch self {
        case .today: return "today_screen"
        case .library: return "library_screen"
        case .profile: return "profile_screen"
        }
    }

    static func destination(forDeepLink name: Notification.Name) -> AFTab? {
        switch name {
        case .deepLinkToCoach:
            return .profile
        case .deepLinkToWorkout:
            return .library
        case .deepLinkToCalendar:
            return .profile
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

    init(selectedTab: AFTab = .today) {
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
    @State private var tabState = AFTabSelectionState(selectedTab: .today)
    @State private var showingWorkoutPlayer = false
    @State private var showSyncDashboard = false
    @State private var profilePath = NavigationPath()
    @State private var showCreateSheet = false
    @State private var activeCreateFlow: CreateFlowPresentation?
    @State private var suppressFloatingChrome = false
    @State private var resetTokens: [AFTab: UUID] = Dictionary(
        uniqueKeysWithValues: AFTab.allCases.map { ($0, UUID()) }
    )

    private var selectedTab: AFTab { tabState.selectedTab }

    var body: some View {
        ZStack {
            DailyDriver.screenBackground.ignoresSafeArea()
            activeDestination

            if !suppressFloatingChrome {
                VStack {
                    Spacer()
                    DDFloatingTabBar(selectedTab: selectedTab, onSelect: selectTab)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        DDCreateFAB {
                            showCreateSheet = true
                        }
                        .padding(.trailing, 18)
                        .padding(.bottom, 92)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onPreferenceChange(SuppressDDChromeKey.self) { suppressFloatingChrome = $0 }
        .environment(\.openCreateSheet, openCreateEntry)
        .createFlowSheets(
            showCreateSheet: $showCreateSheet,
            activeFlow: $activeCreateFlow,
            onLibraryReload: notifyLibraryReload
        )
        .tint(DailyDriver.lime)
        .task {
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
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToCalendar)) { note in
            routeDeepLink(.deepLinkToCalendar)
            if let date = note.userInfo?["date"] as? String {
                viewModel.preselectCalendarDate(date)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToCoach)) { note in
            routeDeepLink(.deepLinkToCoach)
            profilePath.append(ProfileHubRoute.coach)
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
            profilePath.append(ProfileHubRoute.settings)
            showSyncDashboard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToNutrition)) { _ in
            routeDeepLink(.deepLinkToNutrition)
            profilePath.append(ProfileHubRoute.settings)
        }
    }

    @ViewBuilder
    private var activeDestination: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_START_SCREEN"] == "programs" {
            ProgramsListView()
        } else {
            activeTabDestination
        }
        #else
        activeTabDestination
        #endif
    }

    @ViewBuilder
    private var activeTabDestination: some View {
        switch selectedTab {
        case .today:
            tabRoot(.today) {
                TodayDiaryView()
            }
        case .library:
            tabRoot(.library) {
                LibraryView()
            }
        case .profile:
            tabRoot(.profile) {
                ProfileHubView(
                    navigateToSyncDashboard: $showSyncDashboard,
                    path: $profilePath
                )
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

    private func openCreateEntry() {
        switch LibraryPasteRouter.destination() {
        case .socialImport(let url, let platform):
            activeCreateFlow = .socialImport(url: url, platform: platform)
        case .knowledge:
            showCreateSheet = true
        }
    }

    private func notifyLibraryReload() {
        NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)
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
        .background {
            Theme.Colors.surface
                .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityIdentifier("af_tabbar")
                .accessibilityLabel("Tab bar")
                .accessibilityElement(children: .ignore)
        }
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

                    Image(systemName: isSelected ? tab.activeIcon : tab.inactiveIcon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.title)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier(tab.accessibilityIdentifier)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutsViewModel())
        .environmentObject(WatchConnectivityManager.shared)
}

#Preview("AFTabBar · Light") {
    AFTabBar(selectedTab: .today) { _ in }
        .background(Theme.Colors.background)
        .environment(\.colorScheme, .light)
}

#Preview("AFTabBar · Dark") {
    AFTabBar(selectedTab: .library) { _ in }
        .background(Theme.Colors.background)
        .environment(\.colorScheme, .dark)
}
