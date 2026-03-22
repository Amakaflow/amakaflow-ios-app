//
//  AnalyticsModels.swift
//  AmakaFlow
//
//  Models for analytics APIs (shoe comparison, etc.) (AMA-1147)
//

import Foundation

// MARK: - Shoe Comparison

struct ShoeStats: Codable, Identifiable {
    let id: String
    let name: String
    let brand: String?
    let totalDistanceKm: Double
    let totalRuns: Int
    let averagePaceMinKm: Double?
    let retiredAt: String?
    let addedAt: String?
}

// MARK: - Subscription / Billing

struct Subscription: Codable {
    let plan: String
    let status: SubscriptionStatus
    let currentPeriodEnd: String?
    let cancelAtPeriodEnd: Bool?
    let features: [String]?
}

enum SubscriptionStatus: String, Codable {
    case active
    case trialing
    case pastDue = "past_due"
    case canceled
    case inactive
}

// MARK: - Notification Preferences

struct NotificationPreferences: Codable {
    var workoutReminders: Bool
    var coachMessages: Bool
    var weeklyReport: Bool
    var conflictAlerts: Bool
    var recoveryReminders: Bool
    var reminderMinutesBefore: Int

    // Training planner constraints (AMA-1133)
    var weeklyVolume: Int
    var hardDayCap: Int
    var runDaysPerWeek: Int
    var goalRace: String?
    var goalRaceDate: String?
    var preferredLongRunDay: Int?

    init(
        workoutReminders: Bool = true,
        coachMessages: Bool = true,
        weeklyReport: Bool = true,
        conflictAlerts: Bool = true,
        recoveryReminders: Bool = true,
        reminderMinutesBefore: Int = 30,
        weeklyVolume: Int = 50,
        hardDayCap: Int = 3,
        runDaysPerWeek: Int = 5,
        goalRace: String? = nil,
        goalRaceDate: String? = nil,
        preferredLongRunDay: Int? = nil
    ) {
        self.workoutReminders = workoutReminders
        self.coachMessages = coachMessages
        self.weeklyReport = weeklyReport
        self.conflictAlerts = conflictAlerts
        self.recoveryReminders = recoveryReminders
        self.reminderMinutesBefore = reminderMinutesBefore
        self.weeklyVolume = weeklyVolume
        self.hardDayCap = hardDayCap
        self.runDaysPerWeek = runDaysPerWeek
        self.goalRace = goalRace
        self.goalRaceDate = goalRaceDate
        self.preferredLongRunDay = preferredLongRunDay
    }
}
