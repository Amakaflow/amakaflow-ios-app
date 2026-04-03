//
//  ProgramsListView.swift
//  AmakaFlow
//
//  List view for Training Programs (AMA-1231)
//

import SwiftUI

struct ProgramsListView: View {
    @StateObject private var viewModel = ProgramsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.programs.isEmpty {
                    loadingState
                } else if let error = viewModel.errorMessage, viewModel.programs.isEmpty {
                    errorState(error)
                } else if viewModel.programs.isEmpty {
                    emptyState
                } else {
                    programsList
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Programs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: ProgramWizardView()) {
                        Image(systemName: "plus")
                            .foregroundColor(Theme.Colors.accentBlue)
                    }
                }
            }
            .refreshable {
                await viewModel.loadPrograms()
            }
            .task {
                if viewModel.programs.isEmpty {
                    await viewModel.loadPrograms()
                }
            }
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("programs_screen")
            }
        }
    }

    // MARK: - Programs List

    private var programsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.programs) { program in
                    NavigationLink(destination: ProgramDetailView(programId: program.id, programName: program.name)) {
                        ProgramCard(program: program)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Theme.Colors.accentBlue)

            Text("Loading programs...")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.surfaceElevated)
                    .frame(width: 80, height: 80)

                Image(systemName: "list.clipboard")
                    .font(.system(size: 36))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text("No Training Programs")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Training programs you create will appear here.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.surfaceElevated)
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundColor(Theme.Colors.accentOrange)
            }

            Text("Something went wrong")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Button {
                Task {
                    await viewModel.loadPrograms()
                }
            } label: {
                Text("Try Again")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Program Card

private struct ProgramCard: View {
    let program: TrainingProgram

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Title row with status badge
            HStack(alignment: .top) {
                Text(program.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)

                Spacer()

                StatusBadge(status: program.status)
            }

            // Description
            if let description = program.description {
                Text(description)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            // Metadata row
            HStack(spacing: Theme.Spacing.md) {
                MetadataTag(icon: "target", text: program.goalDisplayName)
                MetadataTag(icon: "calendar", text: "\(program.durationWeeks)w")
                MetadataTag(icon: "figure.run", text: "\(program.sessionsPerWeek)x/wk")
                MetadataTag(icon: "chart.bar", text: program.experienceLevelDisplayName)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: String

    private var color: Color {
        switch status {
        case "active": return Theme.Colors.accentGreen
        case "completed": return Theme.Colors.accentBlue
        case "draft": return Theme.Colors.textSecondary
        case "archived": return Theme.Colors.textTertiary
        default: return Theme.Colors.textSecondary
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(Theme.Typography.footnote)
            .foregroundColor(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(Theme.CornerRadius.sm)
    }
}

// MARK: - Metadata Tag

private struct MetadataTag: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(Theme.Typography.footnote)
        }
        .foregroundColor(Theme.Colors.textSecondary)
    }
}

// MARK: - Preview

#Preview {
    ProgramsListView()
        .preferredColorScheme(.dark)
}
