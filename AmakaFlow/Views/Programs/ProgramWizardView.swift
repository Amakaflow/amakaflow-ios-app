//
//  ProgramWizardView.swift
//  AmakaFlow
//
//  Multi-step program creation wizard (AMA-1413)
//

import SwiftUI

struct ProgramWizardView: View {
    @StateObject private var viewModel = ProgramWizardViewModel()
    @Environment(\.dismiss) private var dismiss

    // Navigation to program detail after generation
    @State private var navigateToProgramId: String?
    @State private var navigateToProgram = false

    var body: some View {
        VStack(spacing: 0) {
            // Step progress bar
            stepProgressBar
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)

            // Step content
            ScrollView {
                VStack {
                    stepContent
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.lg)
                }
            }

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
                .background(Theme.Colors.background)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle(viewModel.currentStep.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .navigationDestination(isPresented: $navigateToProgram) {
            if let id = navigateToProgramId {
                ProgramDetailView(programId: id, programName: "Your Program")
            }
        }
    }

    // MARK: - Step Progress Bar

    private var stepProgressBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(ProgramWizardViewModel.Step.allCases, id: \.rawValue) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step.rawValue <= viewModel.currentStep.rawValue
                          ? Theme.Colors.accentBlue
                          : Theme.Colors.surfaceElevated)
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.currentStep)
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .goal:
            GoalStepView(viewModel: viewModel)
        case .experience:
            ExperienceStepView(viewModel: viewModel)
        case .schedule:
            ScheduleStepView(viewModel: viewModel)
        case .equipment:
            EquipmentStepView(viewModel: viewModel)
        case .preferences:
            PreferencesStepView(viewModel: viewModel)
        case .review:
            ReviewStepView(viewModel: viewModel) { programId in
                navigateToProgramId = programId
                navigateToProgram = true
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Primary action button
            if viewModel.currentStep == .review && viewModel.generatedProgramId == nil && !viewModel.isGenerating {
                Button {
                    Task {
                        await viewModel.generateProgram()
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "sparkles")
                        Text("Generate Program")
                    }
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
                }
            } else if viewModel.currentStep != .review || viewModel.generatedProgramId == nil {
                Button {
                    viewModel.nextStep()
                } label: {
                    Text("Continue")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(viewModel.canAdvance ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                        .cornerRadius(Theme.CornerRadius.md)
                }
                .disabled(!viewModel.canAdvance || viewModel.currentStep == .review)
            }

            // Back button
            if viewModel.currentStep.rawValue > 0 && !viewModel.isGenerating {
                Button {
                    viewModel.previousStep()
                } label: {
                    Text("Back")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProgramWizardView()
        .preferredColorScheme(.dark)
}
