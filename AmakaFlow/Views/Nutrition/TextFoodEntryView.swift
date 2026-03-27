//
//  TextFoodEntryView.swift
//  AmakaFlow
//
//  Free-text food entry with Claude parsing (AMA-1294).
//  User types food description, calls POST /nutrition/parse-text.
//

import SwiftUI

struct TextFoodEntryView: View {
    @ObservedObject var viewModel: FoodLoggingViewModel
    @State private var foodText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // Input area
                inputSection

                // Error
                if let error = viewModel.errorMessage, viewModel.selectedTab == .text {
                    ErrorBanner(message: error)
                }

                // Results
                if !viewModel.textItems.isEmpty {
                    resultsSection
                }

                // Empty state hint
                if viewModel.textItems.isEmpty && !viewModel.isLoading {
                    hintSection
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TextEditor(text: $foodText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100, maxHeight: 150)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.surface)
                .cornerRadius(12)
                .overlay(
                    Group {
                        if foodText.isEmpty {
                            Text("Describe what you ate...\ne.g. \"2 eggs, toast with butter, and a banana\"")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .padding(Theme.Spacing.md)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
                .focused($isTextFieldFocused)

            Button {
                isTextFieldFocused = false
                Task {
                    await viewModel.parseText(text: foodText)
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if viewModel.isLoading && viewModel.selectedTab == .text {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Analyze Food")
                }
                .font(Theme.Typography.bodyBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.md)
                .background(foodText.count >= 3 ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                .cornerRadius(12)
            }
            .disabled(foodText.count < 3 || viewModel.isLoading)
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let totals = viewModel.textTotals {
                MacroTotalsBar(totals: totals)
            }

            ForEach(viewModel.textItems) { item in
                FoodItemRow(item: item)
            }

            Button {
                foodText = ""
                viewModel.textItems = []
                viewModel.textTotals = nil
                viewModel.errorMessage = nil
            } label: {
                Text("Log Another Meal")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.accentBlue)
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.Colors.accentBlue.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Hints

    private var hintSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Tips for better results")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HintRow(text: "Include quantities: \"2 eggs\" not just \"eggs\"")
                HintRow(text: "Mention cooking methods: \"grilled chicken\"")
                HintRow(text: "Include sides and drinks")
                HintRow(text: "Be specific about brands when possible")
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }
}

struct HintRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "F59E0B"))

            Text(text)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

#if DEBUG
struct TextFoodEntryView_Previews: PreviewProvider {
    static var previews: some View {
        TextFoodEntryView(viewModel: FoodLoggingViewModel())
            .preferredColorScheme(.dark)
    }
}
#endif
