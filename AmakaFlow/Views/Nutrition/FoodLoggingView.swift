//
//  FoodLoggingView.swift
//  AmakaFlow
//
//  Tab view for AI food logging (AMA-1294).
//  Provides photo, barcode, and text input tabs.
//

import SwiftUI

struct FoodLoggingView: View {
    @StateObject private var viewModel = FoodLoggingViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                tabBar

                // Tab content
                TabView(selection: $viewModel.selectedTab) {
                    MealPhotoView(viewModel: viewModel)
                        .tag(FoodLoggingTab.photo)

                    BarcodeScannerView(viewModel: viewModel)
                        .tag(FoodLoggingTab.barcode)

                    TextFoodEntryView(viewModel: viewModel)
                        .tag(FoodLoggingTab.text)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Theme.Colors.background)
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(Theme.Colors.accentBlue)
                    }
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(FoodLoggingTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18))

                        Text(tab.rawValue)
                            .font(Theme.Typography.caption)
                    }
                    .foregroundColor(viewModel.selectedTab == tab
                        ? Theme.Colors.accentBlue
                        : Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .background(Theme.Colors.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.Colors.borderLight),
            alignment: .bottom
        )
    }
}

// MARK: - Shared Components

struct FoodItemRow: View {
    let item: FoodItemResponse

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(item.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                if let confidence = item.confidence {
                    ConfidenceBadge(level: confidence)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                MacroLabel(label: "Cal", value: item.calories, unit: "")
                MacroLabel(label: "P", value: item.proteinG, unit: "g")
                MacroLabel(label: "C", value: item.carbsG, unit: "g")
                MacroLabel(label: "F", value: item.fatG, unit: "g")
            }

            if let serving = item.servingSize {
                Text(serving)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }
}

struct MacroLabel: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)

            Text("\(Int(value))\(unit)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

struct MacroTotalsBar: View {
    let totals: MacroTotalsResponse

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            MacroTotal(label: "Calories", value: "\(Int(totals.calories))", color: Theme.Colors.accentOrange)
            MacroTotal(label: "Protein", value: "\(Int(totals.proteinG))g", color: Theme.Colors.accentBlue)
            MacroTotal(label: "Carbs", value: "\(Int(totals.carbsG))g", color: Theme.Colors.accentGreen)
            MacroTotal(label: "Fat", value: "\(Int(totals.fatG))g", color: Color(hex: "F59E0B"))
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surfaceElevated)
        .cornerRadius(12)
    }
}

struct MacroTotal: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(color)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ConfidenceBadge: View {
    let level: String

    var body: some View {
        Text(level.capitalized)
            .font(Theme.Typography.footnote)
            .foregroundColor(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .cornerRadius(8)
    }

    private var badgeColor: Color {
        switch level.lowercased() {
        case "high": return Theme.Colors.accentGreen
        case "medium": return Color(hex: "F59E0B")
        case "low": return Theme.Colors.accentRed
        default: return Theme.Colors.textSecondary
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.Colors.accentRed)

            Text(message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.accentRed.opacity(0.1))
        .cornerRadius(8)
    }
}

#if DEBUG
struct FoodLoggingView_Previews: PreviewProvider {
    static var previews: some View {
        FoodLoggingView()
            .preferredColorScheme(.dark)
    }
}
#endif
