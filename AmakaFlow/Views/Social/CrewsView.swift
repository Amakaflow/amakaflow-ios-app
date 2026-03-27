//
//  CrewsView.swift
//  AmakaFlow
//
//  List my training crews + create/join actions (AMA-1277)
//

import SwiftUI

struct CrewsView: View {
    @StateObject private var viewModel = CrewsViewModel()
    @State private var showingCreateSheet = false
    @State private var showingJoinSheet = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.crews.isEmpty {
                ProgressView("Loading crews...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.crews.isEmpty && viewModel.errorMessage == nil {
                emptyState
            } else {
                crewsList
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Crews")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Label("Create Crew", systemImage: "plus.circle")
                    }
                    Button {
                        showingJoinSheet = true
                    } label: {
                        Label("Join with Code", systemImage: "person.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }
        }
        .refreshable {
            await viewModel.loadCrews()
        }
        .task {
            if viewModel.crews.isEmpty {
                await viewModel.loadCrews()
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateCrewView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingJoinSheet) {
            JoinCrewView(viewModel: viewModel)
        }
    }

    // MARK: - Crews List

    private var crewsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                        .padding(.horizontal, Theme.Spacing.md)
                }

                ForEach(viewModel.crews) { crew in
                    NavigationLink {
                        CrewDetailView(crewId: crew.id, viewModel: viewModel)
                    } label: {
                        crewCard(crew)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Crew Card

    private func crewCard(_ crew: Crew) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(crew.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if let desc = crew.description, !desc.isEmpty {
                        Text(desc)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(crew.memberCount)/\(crew.maxMembers)")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("members")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.Colors.accentBlue.opacity(0.5), lineWidth: 2)
        )
        .cornerRadius(12)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.accentBlue)

            Text("No crews yet")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Create a training crew or join one with an invite code.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Text("Create")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(10)
                }

                Button {
                    showingJoinSheet = true
                } label: {
                    Text("Join")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.accentBlue)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Theme.Colors.accentBlue, lineWidth: 1.5)
                        )
                        .cornerRadius(10)
                }
            }
        }
        .padding(Theme.Spacing.xl)
    }
}

#Preview {
    NavigationStack {
        CrewsView()
    }
    .preferredColorScheme(.dark)
}
