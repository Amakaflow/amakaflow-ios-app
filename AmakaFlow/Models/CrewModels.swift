//
//  CrewModels.swift
//  AmakaFlow
//
//  Models for Training Crews — private groups with shared feed (AMA-1277)
//

import Foundation

// MARK: - Crew

struct Crew: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let createdBy: String
    let maxMembers: Int
    let inviteCode: String
    let memberCount: Int
    let createdAt: String
}

// MARK: - Crew Member

struct CrewMember: Identifiable, Codable, Equatable {
    var id: String { userId }
    let userId: String
    let role: String
    let joinedAt: String

    var isAdmin: Bool { role == "admin" }
}

// MARK: - Crew Detail

struct CrewDetail: Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let createdBy: String
    let maxMembers: Int
    let inviteCode: String
    let members: [CrewMember]
    let memberCount: Int
    let createdAt: String
}

// MARK: - Crew Feed Post

struct CrewFeedPost: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let content: [String: String]?
    let photoUrl: String?
    let prBadges: [String]
    let createdAt: String

    var workoutName: String {
        content?["workout_name"] ?? "Workout"
    }
}

// MARK: - API Requests

struct CreateCrewRequest: Codable {
    let name: String
    let description: String?
    let maxMembers: Int
}

struct JoinCrewRequest: Codable {
    let inviteCode: String
}

struct CreateCrewChallengeRequest: Codable {
    let title: String
    let type: String
    let metric: String
    let target: Double
    let startDate: String
    let endDate: String
    let description: String?
}

// MARK: - API Responses

struct CrewListResponse: Codable {
    let crews: [Crew]
    let count: Int
}

struct CrewFeedResponse: Codable {
    let posts: [CrewFeedPost]
    let nextCursor: String?
}

struct JoinCrewResponse: Codable {
    let status: String
    let crewId: String
    let userId: String
}

struct LeaveCrewResponse: Codable {
    let status: String
    let crewId: String
    let userId: String
}

struct CrewChallengeResponse: Codable {
    let id: String
    let crewId: String
    let title: String
    let status: String
}
