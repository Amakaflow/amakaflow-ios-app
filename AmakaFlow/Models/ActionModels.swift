//
//  ActionModels.swift
//  AmakaFlow
//
//  Models for pending actions / activity feed APIs (AMA-1147)
//

import Foundation

// MARK: - Pending Actions

struct PendingAction: Codable, Identifiable {
    let id: String
    let type: ActionType
    let title: String
    let description: String?
    let createdAt: String?
    let metadata: ActionMetadata?
    let status: ActionStatus
}

enum ActionType: String, Codable {
    case workoutSuggestion = "workout_suggestion"
    case scheduleChange = "schedule_change"
    case recoveryReminder = "recovery_reminder"
    case goalUpdate = "goal_update"
    case general
}

enum ActionStatus: String, Codable {
    case pending
    case approved
    case rejected
    case undone
}

struct ActionMetadata: Codable {
    let workoutId: String?
    let date: String?
    let priority: String?
}

struct ActionResponse: Codable {
    let success: Bool
    let message: String?
}
