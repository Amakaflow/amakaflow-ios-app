//
//  CoachModels.swift
//  AmakaFlow
//
//  Models for coach chat, fatigue advice, and coach memory APIs (AMA-1147)
//

import Foundation

// MARK: - Coach Message

struct CoachMessageRequest: Codable {
    let message: String
    let context: CoachContext?
}

struct CoachContext: Codable {
    let currentDate: String?
    let recentWorkouts: [String]?
}

struct CoachResponse: Codable, Identifiable {
    let id: String?
    let message: String
    let suggestions: [CoachSuggestion]?
    let actionItems: [CoachActionItem]?

    var stableId: String { id ?? UUID().uuidString }
}

struct CoachSuggestion: Codable, Identifiable {
    let id: String?
    let text: String
    let type: SuggestionType?

    var stableId: String { id ?? UUID().uuidString }
}

enum SuggestionType: String, Codable {
    case workout
    case recovery
    case nutrition
    case general
}

struct CoachActionItem: Codable, Identifiable {
    let id: String?
    let title: String
    let description: String?
    let actionType: String?

    var stableId: String { id ?? UUID().uuidString }
}

// MARK: - Fatigue Advice

struct FatigueAdviceRequest: Codable {
    let currentFatigueScore: Double?
    let recentLoadHistory: [DailyLoad]?
}

struct DailyLoad: Codable {
    let date: String
    let loadScore: Double
}

struct FatigueAdvice: Codable {
    let level: FatigueLevel
    let message: String
    let recommendations: [String]
    let suggestedRestDays: Int?
    let recoveryActivities: [String]?
}

enum FatigueLevel: String, Codable {
    case low
    case moderate
    case high
    case critical
}

// MARK: - Coach Memory

struct CoachMemory: Codable, Identifiable {
    let id: String
    let content: String
    let category: String?
    let createdAt: String?
    let relevance: Double?
}
