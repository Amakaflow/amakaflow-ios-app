//
//  BulkImportWizardView.swift
//  AmakaFlow
//
//  Main container for the 5-step bulk import wizard (AMA-1415)
//

import SwiftUI

struct BulkImportWizardView: View {
    @StateObject private var viewModel = BulkImportViewModel()

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Step indicator
                stepIndicator
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)

                Divider()
                    .background(Theme.Colors.borderLight)

                // Step content
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Bulk Import")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(BulkImportViewModel.Step.allCases, id: \.rawValue) { step in
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(stepIndicatorColor(step))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("\(step.rawValue + 1)")
                                .font(Theme.Typography.footnote)
                                .foregroundColor(.white)
                        )

                    if step != BulkImportViewModel.Step.allCases.last {
                        Rectangle()
                            .fill(step.rawValue < viewModel.currentStep.rawValue
                                  ? Theme.Colors.accentBlue
                                  : Theme.Colors.borderLight)
                            .frame(height: 2)
                    }
                }
            }
        }
    }

    private func stepIndicatorColor(_ step: BulkImportViewModel.Step) -> Color {
        if step.rawValue < viewModel.currentStep.rawValue {
            return Theme.Colors.accentGreen
        } else if step == viewModel.currentStep {
            return Theme.Colors.accentBlue
        } else {
            return Theme.Colors.borderMedium
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .source:
            SourceSelectionView(viewModel: viewModel)
        case .detect:
            DetectionResultsView(viewModel: viewModel)
        case .match:
            ExerciseMatchingView(viewModel: viewModel)
        case .preview:
            ImportPreviewView(viewModel: viewModel)
        case .importing:
            ImportProgressView(viewModel: viewModel)
        }
    }
}
