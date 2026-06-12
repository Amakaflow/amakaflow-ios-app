//
//  AmakaFlowCompanionTests.swift
//  AmakaFlowCompanionTests
//
//  Created by DAVID ANDREWS on 11/21/25.
//
// Note: trivial touch on the #321 build-once PR to make affected-tests-ios.sh
// flag iOS sources, so the ios-tests job runs and validates that it can
// consume the shared build's products (test-without-building). Safe to remove.

import Testing
@testable import AmakaFlowCompanion

struct AmakaFlowCompanionTests {

    @Test func sixTabSelectionSwitchesAndRetapRequestsRootPop() async throws {
        var state = AFTabSelectionState(selectedTab: .home)

        #expect(state.selectedTab == .home)
        #expect(state.select(.workouts) == .switchTo(.workouts))
        #expect(state.selectedTab == .workouts)

        #expect(state.select(.workouts) == .popToRoot(.workouts))
        #expect(state.selectedTab == .workouts)
        #expect(state.resetCount(for: .workouts) == 1)
    }

    @Test func sixTabDeepLinksMapToTopLevelDestinations() async throws {
        #expect(AFTab.destination(forDeepLink: .deepLinkToCoach) == .coach)
        #expect(AFTab.destination(forDeepLink: .deepLinkToWorkout) == .workouts)
        #expect(AFTab.destination(forDeepLink: .deepLinkToCalendar) == .workouts)
        #expect(AFTab.destination(forDeepLink: .deepLinkToSync) == .profile)
        #expect(AFTab.destination(forDeepLink: .deepLinkToNutrition) == .profile)
    }

    @Test func sixTabMetadataMatchesDesignContract() async throws {
        #expect(AFTab.allCases.map(\.title) == ["Home", "Workouts", "Coach", "Library", "History", "Profile"])
        #expect(AFTab.allCases.map(\.accessibilityIdentifier) == [
            "home_tab",
            "workouts_tab",
            "coach_tab",
            "library_tab",
            "history_tab",
            "profile_tab"
        ])
    }
}
