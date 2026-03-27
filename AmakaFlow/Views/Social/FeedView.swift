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
