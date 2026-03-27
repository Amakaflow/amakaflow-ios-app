//
//  LeaderboardModels.swift
//  AmakaFlow
//
//  Models for multi-dimension leaderboards — friends and crew scopes (AMA-1278)
//

import Foundation

// MARK: - Enums

enum LeaderboardDimension: String, CaseIterable, Identifiable {
    case consistency
    case volume
    case prs
    case workouts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .consistency: return "Consistency"
        case .volume: return "Volume"
        case .prs: return "PRs"
        case .workouts: return "Workouts"
        }
    }

    var unit: String {
        switch self {
        case .consistency: return "weeks"
        case .volume: return "kg"
        case .prs: return "PRs"
        case .workouts: return "workouts"
        }
    }
}

enum LeaderboardPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case allTime = "all_time"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week: return "This Week"
        case .month: return "This Month"
        case .allTime: return "All Time"
        }
    }
}

enum LeaderboardScope: String, CaseIterable, Identifiable {
    case friends
    case crew

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .friends: return "Friends"
        case .crew: return "Crew"
        }
    }
}

// MARK: - Leaderboard Entry

struct LeaderboardEntryModel: Identifiable, Codable, Equatable {
    var id: String { userId }
    let rank: Int
    let userId: String
    let displayName: String
    let avatarUrl: String?
    let value: Double
    let isMe: Bool
}

// MARK: - API Response

struct LeaderboardAPIResponse: Codable {
    let dimension: String
    let period: String
    let entries: [LeaderboardEntryModel]
}
