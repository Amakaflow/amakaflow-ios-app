//
//  SourcesView.swift
//  AmakaFlow
//
//  Sources screen for connecting workout sources and importing videos
//

import SwiftUI

struct SourcesView: View {
    @EnvironmentObject var viewModel: WorkoutsViewModel
    @AppStorage("instagramImportMode") private var instagramImportMode: InstagramImportMode = .manual
    @State private var showingAppleWorkouts = false
    @State private var showingAIImport = false
    @State private var showingImageImport = false
    @State private var showingInstagramImport = false
    @State private var showingManualInstagramImport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Connected section
                    connectedSection

                    // Import From section
                    importSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
                .padding(.bottom, 100) // Space for tab bar
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.large)
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("sources_screen")
            }
            .sheet(isPresented: $showingInstagramImport) {
                InstagramReelIngestionView(apiService: APIService.shared)
            }
            .sheet(isPresented: $showingManualInstagramImport) {
                ManualInstagramIngestionView(apiService: APIService.shared)
            }
        }
    }

    // MARK: - Connected Section

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("CONNECTED")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.sm) {
                // Apple Workouts
                SourceRow(
                    icon: "apple.logo",
                    iconColor: Theme.Colors.textSecondary,
                    title: "Apple Workouts",
                    subtitle: "\(viewModel.incomingWorkouts.count) workouts synced",
                    action: { showingAppleWorkouts = true }
                )

                // Apple Watch
                SourceRow(
                    icon: "applewatch",
                    iconColor: Theme.Colors.accentGreen,
                    title: "Apple Watch",
                    subtitle: "Connected",
                    badge: "Connected",
                    badgeColor: Theme.Colors.accentGreen,
                    action: {}
                )
            }
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("IMPORT FROM")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.sm) {
                // YouTube
                SourceRow(
                    icon: "play.rectangle.fill",
                    iconColor: Color(hex: "FF0000"),
                    title: "YouTube",
                    subtitle: "Paste link or browse imports",
                    badge: "3 new",
                    badgeColor: Theme.Colors.accentOrange,
                    action: {}
                )

                // Instagram
                SourceRow(
                    icon: "camera.fill",
                    iconColor: Color(hex: "E4405F"),
                    title: "Instagram",
                    subtitle: instagramImportMode == .automatic
                        ? "Import from saved reels"
                        : "Paste caption text",
                    action: {
                        switch instagramImportMode {
                        case .automatic:
                            showingInstagramImport = true
                        case .manual:
                            showingManualInstagramImport = true
                        }
                    }
                )

                // TikTok
                SourceRow(
                    icon: "music.note",
                    iconColor: Color(hex: "00F2EA"),
                    title: "TikTok",
                    subtitle: "Import workout videos",
                    badge: "1 new",
                    badgeColor: Theme.Colors.accentOrange,
                    action: {}
                )

                // AI Import
                SourceRow(
                    icon: "sparkles",
                    iconColor: Color(hex: "8B5CF6"),
                    title: "AI Import",
                    subtitle: "Paste any workout link",
                    isGradient: true,
                    action: { showingAIImport = true }
                )

                // Image Import
                SourceRow(
                    icon: "camera.viewfinder",
                    iconColor: Theme.Colors.accentGreen,
                    title: "Image Import",
                    subtitle: "Scan workout from photo",
                    isGradient: true,
                    action: { showingImageImport = true }
                )

                // Calendar Sync
                SourceRow(
                    icon: "calendar",
                    iconColor: Theme.Colors.accentBlue,
                    title: "Calendar Sync",
                    subtitle: "Runna, TrainingPeaks, etc.",
                    action: {}
                )

                // JSON / FIT Files
                SourceRow(
                    icon: "doc.text",
                    iconColor: Theme.Colors.accentGreen,
                    title: "JSON / FIT Files",
                    subtitle: "Import workout files",
                    action: {}
                )
            }
        }
    }
}

// MARK: - Source Row

private struct SourceRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var badge: String? = nil
    var badgeColor: Color = .clear
    var isGradient: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                // Icon
                ZStack {
                    if isGradient {
                        LinearGradient(
                            colors: [Color(hex: "8B5CF6"), Theme.Colors.accentBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 48, height: 48)
                        .cornerRadius(Theme.CornerRadius.md)
                    } else {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(iconColor.opacity(0.1))
                            .frame(width: 48, height: 48)
                    }

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(isGradient ? .white : iconColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        if let badge = badge {
                            Text(badge)
                                .font(Theme.Typography.footnote)
                                .foregroundColor(badgeColor)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(badgeColor.opacity(0.1))
                                .cornerRadius(Theme.CornerRadius.sm)
                        }
                    }

                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SourcesView()
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}
