//
//  FeedView.swift
//  AmakaFlow
//
//  Community feed showing workout posts from followed users (AMA-1273)
//

import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showingCommentSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.posts.isEmpty {
                    ProgressView("Loading feed...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.posts.isEmpty && viewModel.errorMessage == nil {
                    emptyState
                } else {
                    feedList
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Social")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.loadFeed()
            }
            .task {
                if viewModel.posts.isEmpty {
                    await viewModel.loadFeed()
                }
            }
            .sheet(isPresented: $showingCommentSheet) {
                CommentSheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - Feed List

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                // Crews section (AMA-1277)
                NavigationLink {
                    CrewsView()
                } label: {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.Colors.accentBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Crews")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("Private training groups")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // Challenges section (AMA-1276)
                NavigationLink {
                    ChallengesView()
                } label: {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "FFD700"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Challenges")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("Browse and join challenges")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // Leaderboards section (AMA-1278)
                NavigationLink {
                    LeaderboardView()
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.Colors.accentBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Leaderboards")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("See how you rank among friends")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)


                ForEach(viewModel.posts) { post in
                    FeedPostCard(
                        post: post,
                        onReact: { emoji in
                            Task { await viewModel.toggleReaction(postId: post.id, emoji: emoji) }
                        },
                        onComment: {
                            Task { await viewModel.loadComments(postId: post.id) }
                            showingCommentSheet = true
                        },
                        onTapUser: { _ in
                            // Navigation to profile handled by NavigationLink inside card
                        }
                    )
                }

                if viewModel.hasMore {
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .padding()
                    } else {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.accentBlue)

            Text("No posts yet")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Follow other athletes to see their workouts here.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
    }
}

#Preview {
    FeedView()
        .preferredColorScheme(.dark)
}
