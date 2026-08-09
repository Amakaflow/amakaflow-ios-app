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
    let onSelect: (AFTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AFTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selectedTab == tab ? tab.activeIcon : tab.inactiveIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(selectedTab == tab ? DailyDriver.lime : DailyDriver.foregroundDim)
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
        .accessibilityIdentifier("af_tabbar")
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
