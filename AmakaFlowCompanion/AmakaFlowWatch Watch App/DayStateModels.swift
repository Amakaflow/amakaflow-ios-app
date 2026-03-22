//
//  DayStateModels.swift
//  AmakaFlowWatch Watch App
//
//  Models for DayState calendar, readiness, coach, and conflict features (AMA-1150)
//

import Foundation
import SwiftUI

// MARK: - DayState (from backend planning API)

/// Represents today's training state including sessions and readiness
struct DayState: Codable, Equatable {
    let date: String
    let readinessScore: Int
    let readinessLabel: ReadinessLabel
    let sessions: [PlannedSession]
    let conflictAlert: ConflictAlert?

    static let empty = DayState(
        date: "",
        readinessScore: 0,
        readinessLabel: .rest,
        sessions: [],
        conflictAlert: nil
    )
}

// MARK: - Readiness

enum ReadinessLabel: String, Codable, Equatable {
    case ready = "ready"
    case moderate = "moderate"
    case rest = "rest"

    var displayText: String {
        switch self {
        case .ready: return "Ready to train"
        case .moderate: return "Take it easy"
        case .rest: return "Rest day"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .green
        case .moderate: return .orange
        case .rest: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .rest: return "moon.fill"
        }
    }
}

// MARK: - Planned Session

struct PlannedSession: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let scheduledTime: String?  // ISO time string e.g. "08:30"
    let sport: String
    let durationMinutes: Int?
    let isCompleted: Bool
    let isNext: Bool            // Whether this is the next upcoming session
}

// MARK: - Conflict Alert

struct ConflictAlert: Codable, Equatable {
    let message: String
    let severity: ConflictSeverity
    let suggestedAction: String?
}

enum ConflictSeverity: String, Codable, Equatable {
    case warning
    case critical
}

// MARK: - Coach Response

struct CoachResponse: Codable, Equatable {
    let answer: String
    let question: String
}

// MARK: - Quick Coach Questions

enum QuickCoachQuestion: String, CaseIterable, Identifiable {
    case howAmIDoing = "How am I doing?"
    case shouldITrain = "Should I train today?"
    case amIRecovered = "Am I recovered?"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .howAmIDoing: return "chart.bar.fill"
        case .shouldITrain: return "figure.run"
        case .amIRecovered: return "heart.fill"
        }
    }
}

// MARK: - Watch Communication Actions (AMA-1150)

/// Message actions for DayState features sent between watch and phone
enum DayStateAction: String {
    case requestDayState = "requestDayState"
    case dayStateResponse = "dayStateResponse"
    case requestCoachAnswer = "requestCoachAnswer"
    case coachResponse = "coachResponse"
    case conflictAction = "conflictAction"
}
