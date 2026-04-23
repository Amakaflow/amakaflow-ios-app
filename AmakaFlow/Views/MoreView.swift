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

    var body: some View {
        NavigationStack {
            List {
                // Primary features — MVP scope keeps History only.
                // AI Coach / Log Food / Sources / Programs are non-MVP and
                // hidden behind FeatureFlags.nonMvp. Code stays in the app
                // so we can re-enable without a re-implementation when the
                // willingness-to-pay test resolves (AMA-1588 / AMA-MVP-06).
                Section {
                    if FeatureFlags.nonMvp {
                        NavigationLink {
                            CoachChatView()
                        } label: {
                            moreRow(icon: "bubble.left.and.bubble.right.fill", title: "AI Coach")
                        }

                        NavigationLink {
                            FoodLoggingView()
                        } label: {
                            moreRow(icon: "fork.knife", title: "Log Food")
                        }
                    }

                    NavigationLink {
                        ActivityHistoryView()
                    } label: {
                        moreRow(icon: "clock.fill", title: "History")
                    }

                    if FeatureFlags.nonMvp {
                        NavigationLink {
                            SourcesView()
                        } label: {
                            moreRow(icon: "arrow.down.circle.fill", title: "Sources")
                        }

                        NavigationLink {
                            ProgramsListView()
                        } label: {
                            moreRow(icon: "list.bullet.clipboard", title: "Programs")
                        }
                    }
                } header: {
                    Text("Features")
                }

                // Tools — all non-MVP for the first cut.
                if FeatureFlags.nonMvp {
                    Section {
                        NavigationLink {
                            FatigueHistoryView()
                        } label: {
                            moreRow(icon: "chart.line.uptrend.xyaxis", title: "Readiness History")
                        }

                        NavigationLink {
                            FatigueAdvisorStandaloneView()
                        } label: {
                            moreRow(icon: "heart.text.square", title: "Fatigue Advisor")
                        }

                        NavigationLink {
                            BulkImportWizardView()
                        } label: {
                            moreRow(icon: "square.and.arrow.down.on.square", title: "Bulk Import")
                        }
                    } header: {
                        Text("Tools")
                    }
                }

                // Settings — always visible.
                Section {
                    NavigationLink {
                        SettingsView(navigateToSyncDashboard: $navigateToSyncDashboard)
                    } label: {
                        moreRow(icon: "gearshape.fill", title: "Settings")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func moreRow(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(Theme.Colors.accentBlue)
                .frame(width: 24)
            Text(title)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Standalone Fatigue Advisor (accessible outside Coach tab)

struct FatigueAdvisorStandaloneView: View {
    @StateObject private var viewModel = CoachViewModel()

    var body: some View {
        FatigueAdvisorView(viewModel: viewModel)
    }
}
