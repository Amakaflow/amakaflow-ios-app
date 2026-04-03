//
//  FatigueHistoryView.swift
//  AmakaFlow
//
//  Readiness history view with date range selection (AMA-1412)
//

import SwiftUI

struct FatigueHistoryView: View {
    @StateObject private var viewModel = FatigueHistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Range", selection: $viewModel.selectedRange) {
                ForEach(FatigueHistoryViewModel.DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Spacing.md)
            .onChange(of: viewModel.selectedRange) { _, newRange in
                viewModel.changeRange(newRange)
            }

            if !viewModel.dayStates.isEmpty {
                HStack(spacing: Theme.Spacing.lg) {
                    if let avg = viewModel.averageFatigueScore {
                        statPill("Avg", value: "\(Int(avg))")
                    }
                    statPill("🟢", value: "\(viewModel.greenDays)")
                    statPill("🟡", value: "\(viewModel.yellowDays)")
                    statPill("🔴", value: "\(viewModel.redDays)")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            }

            if viewModel.isLoading {
                ProgressView("Loading history...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.accentRed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.dayStates.isEmpty {
                Text("No readiness data available yet.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.dayStates) { dayState in
                    dayRow(dayState)
                        .listRowBackground(Theme.Colors.surface)
                }
                .listStyle(.plain)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Readiness History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadHistory()
        }
    }

    private func statPill(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func dayRow(_ dayState: DayState) -> some View {
        HStack {
            Text(dayState.date)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            readinessBadge(dayState.readiness)
            if let score = dayState.fatigueScore {
                Text("\(Int(score))")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func readinessBadge(_ level: ReadinessLevel) -> some View {
        Text(level.rawValue.capitalized)
            .font(Theme.Typography.captionBold)
            .foregroundColor(readinessColor(level))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(readinessColor(level).opacity(0.15))
            .cornerRadius(Theme.CornerRadius.sm)
    }

    private func readinessColor(_ level: ReadinessLevel) -> Color {
        switch level {
        case .green: return Theme.Colors.accentGreen
        case .yellow: return Theme.Colors.accentOrange
        case .red: return Theme.Colors.accentRed
        case .rest: return Theme.Colors.accentBlue
        case .unknown: return Theme.Colors.textTertiary
        }
    }
}
