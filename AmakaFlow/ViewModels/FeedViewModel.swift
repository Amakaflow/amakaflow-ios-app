//
//  FeedViewModel.swift
//  AmakaFlow
//
//  ViewModel for community feed — pagination, reactions, comments (AMA-1273)
//

import Foundation
import Combine

@MainActor
class FeedViewModel: ObservableObject {
    @Published var posts: [FeedPost] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var nextCursor: String?
    @Published var hasMore = false

    // Comment sheet state
    @Published var selectedPostId: String?
    @Published var comments: [FeedComment] = []
    @Published var isLoadingComments = false
    @Published var commentText = ""
    @Published var isPostingComment = false

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Feed

    func loadFeed() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await dependencies.apiService.fetchSocialFeed(cursor: nil, limit: 20)
            posts = response.posts
            nextCursor = response.nextCursor
            hasMore = response.hasMore
        } catch {
            errorMessage = "Could not load feed: \(error.localizedDescription)"
            print("[FeedViewModel] loadFeed failed: \(error)")
        }

        isLoading = false
    }

    func loadMore() async {
        guard let cursor = nextCursor, hasMore, !isLoadingMore else { return }
        isLoadingMore = true

        do {
            let response = try await dependencies.apiService.fetchSocialFeed(cursor: cursor, limit: 20)
            posts.append(contentsOf: response.posts)
            nextCursor = response.nextCursor
            hasMore = response.hasMore
        } catch {
            print("[FeedViewModel] loadMore failed: \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - Reactions

    func toggleReaction(postId: String, emoji: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }

        let hasReacted = posts[index].userReactions.contains(emoji)

        // Optimistic update
        var updatedPost = posts[index]
        var userReactions = updatedPost.userReactions
        var reactions = updatedPost.reactions

        if hasReacted {
            userReactions.removeAll { $0 == emoji }
            if let rIdx = reactions.firstIndex(where: { $0.emoji == emoji }) {
                let newCount = reactions[rIdx].count - 1
                if newCount > 0 {
                    reactions[rIdx] = FeedReaction(emoji: emoji, count: newCount)
                } else {
                    reactions.remove(at: rIdx)
                }
            }
        } else {
            userReactions.append(emoji)
            if let rIdx = reactions.firstIndex(where: { $0.emoji == emoji }) {
                reactions[rIdx] = FeedReaction(emoji: emoji, count: reactions[rIdx].count + 1)
            } else {
                reactions.append(FeedReaction(emoji: emoji, count: 1))
            }
        }

        updatedPost = FeedPost(
            id: updatedPost.id,
            userId: updatedPost.userId,
            userName: updatedPost.userName,
            userAvatarUrl: updatedPost.userAvatarUrl,
            postedAt: updatedPost.postedAt,
            workoutName: updatedPost.workoutName,
            exercises: updatedPost.exercises,
            totalVolume: updatedPost.totalVolume,
            durationSeconds: updatedPost.durationSeconds,
            personalRecords: updatedPost.personalRecords,
            photoUrl: updatedPost.photoUrl,
            reactions: reactions,
            commentCount: updatedPost.commentCount,
            userReactions: userReactions
        )
        posts[index] = updatedPost

        do {
            if hasReacted {
                try await dependencies.apiService.removeSocialReaction(postId: postId, emoji: emoji)
            } else {
                try await dependencies.apiService.addSocialReaction(postId: postId, emoji: emoji)
            }
        } catch {
            // Revert on failure — reload
            print("[FeedViewModel] toggleReaction failed: \(error)")
            await loadFeed()
        }
    }

    // MARK: - Comments

    func loadComments(postId: String) async {
        selectedPostId = postId
        isLoadingComments = true
        comments = []

        do {
            let response = try await dependencies.apiService.fetchSocialComments(postId: postId)
            comments = response.comments
        } catch {
            print("[FeedViewModel] loadComments failed: \(error)")
        }

        isLoadingComments = false
    }

    func postComment() async {
        guard let postId = selectedPostId, !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPostingComment = true

        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await dependencies.apiService.postSocialComment(postId: postId, text: text)
            commentText = ""
            await loadComments(postId: postId)

            // Update comment count in feed
            if let index = posts.firstIndex(where: { $0.id == postId }) {
                let post = posts[index]
                posts[index] = FeedPost(
                    id: post.id, userId: post.userId, userName: post.userName,
                    userAvatarUrl: post.userAvatarUrl, postedAt: post.postedAt,
                    workoutName: post.workoutName, exercises: post.exercises,
                    totalVolume: post.totalVolume, durationSeconds: post.durationSeconds,
                    personalRecords: post.personalRecords, photoUrl: post.photoUrl,
                    reactions: post.reactions, commentCount: post.commentCount + 1,
                    userReactions: post.userReactions
                )
            }
        } catch {
            print("[FeedViewModel] postComment failed: \(error)")
        }

        isPostingComment = false
    }
}
