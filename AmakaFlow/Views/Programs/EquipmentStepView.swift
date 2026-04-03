//
//  EquipmentStepView.swift
//  AmakaFlow
//
//  Wizard step 4: Choose available equipment (AMA-1413)
//

import SwiftUI

struct EquipmentStepView: View {
    @ObservedObject var viewModel: ProgramWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("What equipment do you have?")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Select a preset or choose your own equipment.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            // Preset buttons
            if !viewModel.useCustomEquipment {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(ProgramWizardViewModel.equipmentPresets, id: \.id) { preset in
                        PresetButton(
                            name: preset.name,
                            itemCount: preset.items.count,
                            isSelected: viewModel.equipmentPreset == preset.id
                        ) {
                            viewModel.equipmentPreset = preset.id
                        }
                    }
                }
            }

            // Custom equipment toggle
            Toggle(isOn: $viewModel.useCustomEquipment) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom Equipment")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Pick exactly what you have available")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .tint(Theme.Colors.accentBlue)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)

            // Custom equipment grid
            if viewModel.useCustomEquipment {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Select your equipment")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    FlowLayout(spacing: Theme.Spacing.sm) {
                        ForEach(ProgramWizardViewModel.availableEquipment, id: \.self) { item in
                            EquipmentChip(
                                label: item,
                                isSelected: viewModel.customEquipment.contains(item)
                            ) {
                                if viewModel.customEquipment.contains(item) {
                                    viewModel.customEquipment.remove(item)
                                } else {
                                    viewModel.customEquipment.insert(item)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.CornerRadius.md)
            }
        }
    }
}

private struct PresetButton: View {
    let name: String
    let itemCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)

                    Text("\(itemCount) equipment items")
                        .font(Theme.Typography.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : Theme.Colors.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.accentBlue : Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(isSelected ? Theme.Colors.accentBlue : Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
}

private struct EquipmentChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(isSelected ? Theme.Colors.accentBlue : Theme.Colors.surfaceElevated)
                .cornerRadius(Theme.CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }
}
