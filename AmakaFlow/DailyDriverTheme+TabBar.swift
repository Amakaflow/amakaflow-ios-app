//
//  DailyDriverTheme+TabBar.swift
//  AmakaFlow
//
//  Floating tab bar + create FAB — kept out of DailyDriverTheme.swift for file_length.
//

import SwiftUI

// MARK: - Floating tab bar + FAB

struct DDFloatingTabBar: View {
    let selectedTab: AFTab
    var badgeCounts: [AFTab: Int] = [:]
    let onSelect: (AFTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AFTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: selectedTab == tab ? tab.activeIcon : tab.inactiveIcon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(selectedTab == tab ? DailyDriver.lime : DailyDriver.foregroundDim)
                                .frame(width: 28, height: 24)
                            let badge = badgeCounts[tab, default: 0]
                            if badge >= 1 {
                                Text(badge > 9 ? "9+" : "\(badge)")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundColor(DailyDriver.ink)
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 14, minHeight: 14)
                                    .background(DailyDriver.lime)
                                    .clipShape(Capsule(style: .continuous))
                                    .offset(x: 8, y: -6)
                                    .accessibilityIdentifier("\(tab.accessibilityIdentifier)_badge")
                            }
                        }
                        Text(tab.title)
                            .ddDisplayText(10, weight: .semibold)
                            .foregroundColor(selectedTab == tab ? DailyDriver.lime : DailyDriver.foregroundDim)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(DailyDriver.tabBarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 15, x: 0, y: 10)
        }
        .padding(.horizontal, 12)
        // A marker, not an identifier on the bar itself: an identifier here
        // overwrites every descendant's, which is what hid today_tab,
        // library_tab and profile_tab from every flow that taps them
        // (AMA-2492). 30 flows assert on af_tabbar, so it has to keep
        // existing as its own element.
        .overlay(alignment: .top) {
            Text(" ")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("af_tabbar")
                .accessibilityLabel("Tab bar")
        }
    }
}

struct DDCreateFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 25, weight: .semibold))
                .foregroundColor(DailyDriver.ink)
                .frame(width: 56, height: 56)
                .background(DailyDriver.lime)
                .clipShape(Circle())
                .ddLimeGlow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add workout")
        .accessibilityIdentifier("af_library_fab")
    }
}
