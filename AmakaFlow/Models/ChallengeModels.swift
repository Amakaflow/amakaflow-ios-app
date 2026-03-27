//
//  ChallengeModels.swift
//  AmakaFlow
//
//  Models for community challenges — browse, join, track, celebrate (AMA-1276)
//

import Foundation

// MARK: - Challenge Type

enum ChallengeType: String, Codable, CaseIterable, Identifiable {
    case volume
    case consistency
    case pr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .volume: return "Volume"
        case .consistency: return "Consistency"
        case .pr: return "PR"
        }
    }
}

// MARK: - Challenge Status

enum ChallengeStatus: String, Codable {
    case active
    case upcoming
    case completed
    case cancelled
}

// MARK: - Challenge

struct Challenge: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let type: ChallengeType
    let status: ChallengeStatus
    let description: String?
    let target: Double
    let targetUnit: String
    let startDate: Date
    let endDate: Date
    let creatorId: String
    let creatorName: String
    let participantCount: Int
    let isTeamMode: Bool
    let isJoined: Bool
    let myProgress: Double?
    let myProgressPercentage: Double?
}

// MARK: - Leaderboard Entry

struct LeaderboardEntry: Identifiable, Codable, Equatable {
    let id: String
    let rank: Int
    let userId: String
    let userName: String
    let userAvatarUrl: String?
    let progress: Double
    let progressPercentage: Double
}

// MARK: - Challenge Progress

struct ChallengeProgress: Codable, Equatable {
    let challengeId: String
    let currentValue: Double
    let targetValue: Double
    let percentage: Double
    let isCompleted: Bool
    let completedAt: Date?
    let badge: ChallengeBadge?
}

// MARK: - Challenge Badge

struct ChallengeBadge: Codable, Equatable {
    let id: String
    let name: String
    let iconName: String
    let description: String
}

// MARK: - Create Challenge Request

struct CreateChallengeRequest: Codable {
    let title: String
    let type: ChallengeType
    let description: String?
    let target: Double
    let targetUnit: String
    let startDate: Date
    let endDate: Date
    let isTeamMode: Bool
}

// MARK: - API Responses

struct ChallengesResponse: Codable {
    let challenges: [Challenge]
}

struct ChallengeDetailResponse: Codable {
    let challenge: Challenge
    let leaderboard: [LeaderboardEntry]
    let myProgress: ChallengeProgress?
}

struct ChallengeLeaderboardResponse: Codable {
    let entries: [LeaderboardEntry]
}

struct ChallengeProgressResponse: Codable {
    let progress: ChallengeProgress
}
