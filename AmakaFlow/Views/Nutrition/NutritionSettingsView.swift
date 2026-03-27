//
//  NutritionSettingsView.swift
//  AmakaFlow
//
//  Privacy controls for nutrition features (AMA-1292).
//

import SwiftUI

struct NutritionSettingsView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Master toggle
                masterToggleSection

                if viewModel.settings.isEnabled {
                    divider

                    // Display mode
                    displayModeSection

                    divider

                    // Targets
                    targetsSection

                    divider

                    // Danger zone
                    dangerZoneSection
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete All Nutrition Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await viewModel.deleteAllData()
                    isDeleting = false
                }
            }
        } message: {
            Text("This will delete all nutrition data that AmakaFlow has written to HealthKit. Data from other apps will not be affected.")
        }
        .accessibilityIdentifier("nutrition_settings_view")
    }

    // MARK: - Master Toggle

    private var masterToggleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "Nutrition Features", icon: "leaf.fill")

            Toggle(isOn: $viewModel.settings.isEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show nutrition features")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("When off, all nutrition UI is hidden")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .tint(Theme.Colors.accentGreen)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.lg)
        }
    }

    // MARK: - Display Mode

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "Display Mode", icon: "eye.fill")

            VStack(spacing: 0) {
                ForEach(NutritionDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.settings.displayMode = mode
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Text(mode.description)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            if viewModel.settings.displayMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.Colors.accentGreen)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .buttonStyle(.plain)

                    if mode != NutritionDisplayMode.allCases.last {
                        Divider()
                            .background(Theme.Colors.borderLight)
                    }
                }
            }
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.lg)

            Text("Default: Qualitative only (no numbers shown)")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    // MARK: - Targets

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "Targets", icon: "target")

            VStack(spacing: Theme.Spacing.md) {
                // Protein target
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Protein target")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\(Int(viewModel.settings.proteinTargetGrams))g")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.accentGreen)
                    }
                    Slider(
                        value: $viewModel.settings.proteinTargetGrams,
                        in: 50...300,
                        step: 10
                    )
                    .tint(Theme.Colors.accentGreen)

                    Text("Recommended: 1.6-2.2g per kg bodyweight")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)

                // Water target
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Water target")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text(String(format: "%.1fL", viewModel.settings.waterTargetML / 1000))
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.accentBlue)
                    }
                    Slider(
                        value: $viewModel.settings.waterTargetML,
                        in: 1000...5000,
                        step: 250
                    )
                    .tint(Theme.Colors.accentBlue)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "Data", icon: "trash")

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text(isDeleting ? "Deleting..." : "Delete all nutrition data")
                        .font(Theme.Typography.body)
                }
                .foregroundColor(Theme.Colors.accentRed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.lg)
            }
            .disabled(isDeleting)

            Text("Only deletes data written by AmakaFlow")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.borderLight)
            .frame(height: 1)
    }
}

#Preview {
    NavigationStack {
        NutritionSettingsView(viewModel: NutritionViewModel())
    }
    .preferredColorScheme(.dark)
}
