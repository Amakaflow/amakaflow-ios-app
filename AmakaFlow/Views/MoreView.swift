//
//  MoreView.swift
//  AmakaFlow
//
//  "More" tab containing secondary features: Sources, Nutrition, Coach,
//  History, Settings, and other tools. Matches Android's MoreScreen pattern.
//  (AMA-1412 — tab consolidation per Apple HIG)
//

import SwiftUI

struct MoreView: View {
    @Binding var navigateToSyncDashboard: Bool
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    AFTopBar(title: "You") {
                        EmptyView()
                    } right: {
                        EmptyView()
                    }
                    .accessibilityHidden(true)

                    AFLabel(text: "Features")
                        .accessibilityHidden(true)

                    VStack(spacing: 0) {
                    // AMA-1632: Coach is the core agent surface for MVP — always visible.
                    NavigationLink {
                        CoachChatView()
                    } label: {
                        moreRow(icon: "bubble.left.and.bubble.right.fill", title: "AI Coach")
                    }
                    .accessibilityIdentifier("more_row_coach")

                    if FeatureFlags.nonMvp {
                        NavigationLink {
                            FoodLoggingView()
                        } label: {
                            moreRow(icon: "fork.knife", title: "Log Food")
                        }
                        .accessibilityIdentifier("more_row_food")
                    }

                    NavigationLink {
                        ActivityHistoryView()
                    } label: {
                        moreRow(icon: "clock.fill", title: "History")
                    }
                    .accessibilityIdentifier("more_row_history")

                    if FeatureFlags.nonMvp {
                        NavigationLink {
                            SourcesView()
                        } label: {
                            moreRow(icon: "arrow.down.circle.fill", title: "Sources")
                        }
                        .accessibilityIdentifier("more_row_sources")

                        NavigationLink {
                            ProgramsListView()
                        } label: {
                            moreRow(icon: "list.bullet.clipboard", title: "Programs")
                        }
                        .accessibilityIdentifier("more_row_programs")
                    }
                    }
                    .rowCard()

                // Tools — all non-MVP for the first cut.
                if FeatureFlags.nonMvp {
                    AFLabel(text: "Tools")
                        .accessibilityHidden(true)
                    VStack(spacing: 0) {
                        NavigationLink {
                            FatigueHistoryView()
                        } label: {
                            moreRow(icon: "chart.line.uptrend.xyaxis", title: "Readiness History")
                        }
                        .accessibilityIdentifier("more_row_readiness_history")

                        NavigationLink {
                            FatigueAdvisorStandaloneView()
                        } label: {
                            moreRow(icon: "heart.text.square", title: "Fatigue Advisor")
                        }
                        .accessibilityIdentifier("more_row_fatigue_advisor")

                        NavigationLink {
                            BulkImportWizardView()
                        } label: {
                            moreRow(icon: "square.and.arrow.down.on.square", title: "Bulk Import")
                        }
                        .accessibilityIdentifier("more_row_bulk_import")
                    }
                    .rowCard()
                }

                // Settings — always visible.
                    AFLabel(text: "Settings")
                        .accessibilityHidden(true)
                    VStack(spacing: 0) {
                    NavigationLink {
                        SettingsView(navigateToSyncDashboard: $navigateToSyncDashboard)
                    } label: {
                        moreRow(icon: "gearshape.fill", title: "Settings")
                    }
                    .accessibilityIdentifier("more_row_settings")
                    }
                    .rowCard()
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private func moreRow(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 24)
            Text(title)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private extension View {
    func rowCard() -> some View {
        self
            .padding(.horizontal, 14)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }
}

// MARK: - Standalone Fatigue Advisor (accessible outside Coach tab)

struct FatigueAdvisorStandaloneView: View {
    @StateObject private var viewModel = CoachViewModel()

    var body: some View {
        FatigueAdvisorView(viewModel: viewModel)
    }
}
