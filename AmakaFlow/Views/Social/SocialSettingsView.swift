//
//  SocialSettingsView.swift
//  AmakaFlow
//
//  Privacy toggles for social features: discoverable, share workouts, hide weights (AMA-1273)
//

import SwiftUI

struct SocialSettingsView: View {
    @State private var settings = SocialSettings.default
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSavedToast = false

    var body: some View {
        List {
            Section {
                Toggle("Discoverable", isOn: $settings.discoverable)
                    .tint(Theme.Colors.accentBlue)
                    .accessibilityIdentifier("toggle_discoverable")

                Text("Allow other users to find you by name or username.")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .listRowSeparator(.hidden)
            } header: {
                Text("Visibility")
            }

            Section {
                Toggle("Share Workouts", isOn: $settings.shareWorkouts)
                    .tint(Theme.Colors.accentBlue)
                    .accessibilityIdentifier("toggle_share_workouts")

                Text("Automatically share completed workouts with your followers.")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .listRowSeparator(.hidden)
            } header: {
                Text("Sharing")
            }

            Section {
                Toggle("Hide Weights", isOn: $settings.hideWeights)
                    .tint(Theme.Colors.accentBlue)
                    .accessibilityIdentifier("toggle_hide_weights")

                Text("Hide specific weights from shared workouts. Only exercise names and sets/reps will be shown.")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .listRowSeparator(.hidden)
            } header: {
                Text("Privacy")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Social Settings")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background.opacity(0.8))
            }
        }
        .overlay(alignment: .bottom) {
            if showSavedToast {
                Text("Settings saved")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentGreen)
                    .cornerRadius(Theme.CornerRadius.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .task {
            await loadSettings()
        }
        .onChange(of: settings) { _ in
            Task { await saveSettings() }
        }
    }

    private func loadSettings() async {
        isLoading = true
        do {
            settings = try await APIService.shared.fetchSocialSettings()
        } catch {
            errorMessage = error.localizedDescription
            print("[SocialSettingsView] loadSettings failed: \(error)")
        }
        isLoading = false
    }

    private func saveSettings() async {
        guard !isLoading else { return }
        isSaving = true
        do {
            try await APIService.shared.updateSocialSettings(settings)
            withAnimation {
                showSavedToast = true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showSavedToast = false
            }
        } catch {
            print("[SocialSettingsView] saveSettings failed: \(error)")
        }
        isSaving = false
    }
}

#Preview {
    NavigationStack {
        SocialSettingsView()
    }
    .preferredColorScheme(.dark)
}
