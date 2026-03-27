//
//  CommentSheet.swift
//  AmakaFlow
//
//  Bottom sheet for viewing and posting comments on feed posts (AMA-1273)
//

import SwiftUI

struct CommentSheet: View {
    @ObservedObject var viewModel: FeedViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoadingComments {
                    Spacer()
                    ProgressView("Loading comments...")
                    Spacer()
                } else if viewModel.comments.isEmpty {
                    Spacer()
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text("No comments yet")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text("Be the first to comment!")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    Spacer()
                } else {
                    commentsList
                }

                Divider()
                    .background(Theme.Colors.borderLight)

                // Input bar
                inputBar
            }
            .background(Theme.Colors.background)
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Comments List

    private var commentsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(viewModel.comments) { comment in
                    commentRow(comment)
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func commentRow(_ comment: FeedComment) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Avatar
            Group {
                if let avatarUrl = comment.userAvatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        commentAvatarPlaceholder(name: comment.userName)
                    }
                } else {
                    commentAvatarPlaceholder(name: comment.userName)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.userName)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(comment.createdAt.timeAgoDisplay())
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Text(comment.text)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
        }
    }

    private func commentAvatarPlaceholder(name: String) -> some View {
        Circle()
            .fill(Theme.Colors.surfaceElevated)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
            )
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Add a comment...", text: $viewModel.commentText)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .focused($isInputFocused)
                .accessibilityIdentifier("comment_input")

            Button {
                Task { await viewModel.postComment() }
            } label: {
                if viewModel.isPostingComment {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(
                            viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Theme.Colors.textTertiary
                                : Theme.Colors.accentBlue
                        )
                }
            }
            .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isPostingComment)
            .accessibilityIdentifier("send_comment_button")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
    }
}
