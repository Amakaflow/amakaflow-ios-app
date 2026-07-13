//
//  AmakaFlowCompanionTests.swift
//  AmakaFlowCompanionTests
//

import Testing
@testable import AmakaFlowCompanion

struct AmakaFlowCompanionTests {

    @Test func threeTabSelectionSwitchesAndRetapRequestsRootPop() async throws {
        var state = AFTabSelectionState(selectedTab: .today)

        #expect(state.selectedTab == .today)
        #expect(state.select(.library) == .switchTo(.library))
        #expect(state.selectedTab == .library)

        #expect(state.select(.library) == .popToRoot(.library))
        #expect(state.selectedTab == .library)
        #expect(state.resetCount(for: .library) == 1)
    }

    @Test func threeTabDeepLinksMapToTopLevelDestinations() async throws {
        #expect(AFTab.destination(forDeepLink: .deepLinkToCoach) == .profile)
        #expect(AFTab.destination(forDeepLink: .deepLinkToWorkout) == .library)
        #expect(AFTab.destination(forDeepLink: .deepLinkToCalendar) == .profile)
        #expect(AFTab.destination(forDeepLink: .deepLinkToSync) == .profile)
        #expect(AFTab.destination(forDeepLink: .deepLinkToNutrition) == .profile)
    }

    @Test func threeTabMetadataMatchesDailyDriverContract() async throws {
        #expect(AFTab.allCases.map(\.title) == ["Today", "Library", "Profile"])
        #expect(AFTab.allCases.map(\.accessibilityIdentifier) == [
            "today_tab",
            "library_tab",
            "profile_tab"
        ])
    }
}
