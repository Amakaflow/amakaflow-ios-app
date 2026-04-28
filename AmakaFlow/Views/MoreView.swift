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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    AFTopBar(title: "You") {
                        EmptyView()
                    } right: {
                        EmptyView()
                    }

                    AFCard(padding: 16) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.Colors.accentBackground)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(Theme.Colors.textPrimary)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text("AmakaFlow Athlete")
                                    .font(Theme.Typography.title3)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text("Hybrid · 8h/wk · Intermediate")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }

                    AFLabel(text: "Features")

                    VStack(spacing: 0) {
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
                    }
                    .rowCard()

                // Tools — all non-MVP for the first cut.
                if FeatureFlags.nonMvp {
                    AFLabel(text: "Tools")
                    VStack(spacing: 0) {
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
                    }
                    .rowCard()
                }

                // Settings — always visible.
                    AFLabel(text: "Settings")
                    VStack(spacing: 0) {
                    NavigationLink {
                        SettingsView(navigateToSyncDashboard: $navigateToSyncDashboard)
                    } label: {
                        moreRow(icon: "gearshape.fill", title: "Settings")
                    }
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
