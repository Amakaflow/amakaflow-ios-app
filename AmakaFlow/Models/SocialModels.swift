//
//  SocialModels.swift
//  AmakaFlow
//
//  Models for community feed, reactions, comments, and social settings (AMA-1273)
//

import Foundation

// MARK: - Feed Post

struct FeedPost: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let userName: String
    let userAvatarUrl: String?
    let postedAt: Date
    let workoutName: String
    let exercises: [FeedExercise]
    let totalVolume: Double?
    let durationSeconds: Int
    let personalRecords: [FeedPR]
    let photoUrl: String?
    let reactions: [FeedReaction]
    let commentCount: Int
    let userReactions: [String] // emoji strings the current user has applied
}

struct FeedExercise: Codable, Equatable {
    let name: String
    let sets: Int?
    let reps: Int?
    let weight: Double?
}

struct FeedPR: Codable, Equatable {
    let exerciseName: String
    let metric: String // e.g. "1RM", "volume", "reps"
    let value: String
}

struct FeedReaction: Codable, Equatable {
    let emoji: String
    let count: Int
}

// MARK: - Feed Response

struct FeedResponse: Codable {
    let posts: [FeedPost]
    let nextCursor: String?
    let hasMore: Bool
}

// MARK: - Comment

struct FeedComment: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let userName: String
    let userAvatarUrl: String?
    let text: String
    let createdAt: Date
}

struct CommentsResponse: Codable {
    let comments: [FeedComment]
}

// MARK: - Social Settings

struct SocialSettings: Codable, Equatable {
    var discoverable: Bool
    var shareWorkouts: Bool
    var hideWeights: Bool

    static let `default` = SocialSettings(
        discoverable: true,
        shareWorkouts: true,
        hideWeights: false
    )
}

// MARK: - User Public Profile

struct UserPublicProfile: Codable, Equatable {
    let userId: String
    let userName: String
    let avatarUrl: String?
    let workoutCount: Int
    let totalVolume: Double
    let streakDays: Int
    let isFollowing: Bool
    let recentWorkouts: [FeedPost]
}
