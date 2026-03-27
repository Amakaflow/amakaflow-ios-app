//
//  CrewDetailView.swift
//  AmakaFlow
//
//  Crew detail: members, feed, challenges, invite code share (AMA-1277)
//

import SwiftUI

struct CrewDetailView: View {
    let crewId: String
    @ObservedObject var viewModel: CrewsViewModel
    @State private var selectedTab = 0
    @State private var showingShareSheet = false
    @State private var showingLeaveAlert = false

    var body: some View {
        Group {
            if viewModel.isLoadingDetail && viewModel.selectedCrewDetail == nil {
                ProgressView("Loading crew...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = viewModel.selectedCrewDetail {
                crewContent(detail)
            } else {
                Text("Crew not found")
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadCrewDetail(id: crewId)
            await viewModel.loadCrewFeed(crewId: crewId)
        }
        .alert("Leave Crew", isPresented: $showingLeaveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task { _ = await viewModel.leaveCrew(crewId: crewId) }
            }
        } message: {
            Text("Are you sure you want to leave this crew?")
        }
    }

    // MARK: - Content

    private func crewContent(_ detail: CrewDetail) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // Header
                VStack(spacing: Theme.Spacing.sm) {
                    Text(detail.name)
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if let desc = detail.description, !desc.isEmpty {
                        Text(desc)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    HStack(spacing: Theme.Spacing.md) {
                        Label("\(detail.memberCount)/\(detail.maxMembers)", systemImage: "person.3")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Colors.textSecondary)

                        // Invite code
                        Button {
                            UIPasteboard.general.string = detail.inviteCode
                        } label: {
                            Label(detail.inviteCode, systemImage: "doc.on.doc")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.Colors.accentBlue)
                        }
                    }
                }
                .padding(Theme.Spacing.md)

                // Tab picker
                Picker("Section", selection: $selectedTab) {
                    Text("Feed").tag(0)
                    Text("Members").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.md)

                if selectedTab == 0 {
                    feedSection
                } else {
                    membersSection(detail)
                }
            }
            .padding(.bottom, 100)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = detail.inviteCode
                    } label: {
                        Label("Copy Invite Code", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        showingLeaveAlert = true
                    } label: {
                        Label("Leave Crew", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }
        }
    }

    // MARK: - Feed Section

    private var feedSection: some View {
        LazyVStack(spacing: Theme.Spacing.sm) {
            if viewModel.isLoadingFeed {
                ProgressView()
                    .padding()
            } else if viewModel.crewFeedPosts.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("No activity yet")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.xl)
            } else {
                ForEach(viewModel.crewFeedPosts) { post in
                    crewFeedCard(post)
                }
            }
        }
    }

    private func crewFeedCard(_ post: CrewFeedPost) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(post.workoutName)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            if !post.prBadges.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "FFD700"))
                    Text("\(post.prBadges.count) PR\(post.prBadges.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "FFD700"))
                }
            }

            Text(post.createdAt)
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(10)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Members Section

    private func membersSection(_ detail: CrewDetail) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(detail.members) { member in
                HStack {
                    Image(systemName: member.isAdmin ? "crown.fill" : "person.fill")
                        .font(.system(size: 16))
                        .foregroundColor(member.isAdmin ? Color(hex: "FFD700") : Theme.Colors.textSecondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.userId)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text(member.isAdmin ? "Admin" : "Member")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CrewDetailView(crewId: "preview", viewModel: CrewsViewModel())
    }
    .preferredColorScheme(.dark)
}
