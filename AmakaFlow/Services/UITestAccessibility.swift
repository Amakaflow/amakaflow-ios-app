//
//  UITestAccessibility.swift
//  AmakaFlow
//
//  Centralized accessibility identifiers for UITEST automation
//

import Foundation

/// Centralized accessibility identifiers for automation testing
struct UITestAccessibility {
    
    // MARK: - Main Navigation (AMA-2292: Today · Library · Profile)
    
    static let tabBar = "af_tabbar"
    static let todayTab = "today_tab"
    /// Legacy alias — prefer `todayTab` for new automation.
    static let homeTab = "today_tab"
    static let libraryTab = "library_tab"
    static let profileTab = "profile_tab"
    /// Coach / History are Profile hub rows, not root tabs (AMA-2292).
    static let coachTab = "coach_tab"
    static let historyTab = "history_tab"
    static let settingsTab = "settings_tab"
    static let calendarTab = "calendar_tab"
    /// Removed from root chrome; schedule deferred off Daily Driver Proto IA.
    static let workoutsTab = "workouts_tab"
    
    // MARK: - Main Screens
    
    static let todayScreen = "today_screen"
    /// Legacy alias — prefer `todayScreen` for new automation.
    static let homeScreen = "today_screen"
    static let workoutsScreen = "workouts_screen"
    static let coachScreen = "coach_screen"
    static let libraryScreen = "library_screen"
    static let historyScreen = "history_screen"
    static let profileScreen = "profile_screen"
    static let settingsScreen = "settings_screen"
    
    // MARK: - Workout Controls
    
    static let startWorkoutButton = "start_workout_button"
    static let pauseWorkoutButton = "pause_workout_button"
    static let resumeWorkoutButton = "resume_workout_button"
    static let skipExerciseButton = "skip_exercise_button"
    static let completeWorkoutButton = "complete_workout_button"
    
    // MARK: - Workout Display
    
    static let currentExerciseLabel = "current_exercise_label"
    static let timerLabel = "timer_label"
    static let heartRateLabel = "heart_rate_label"
    static let progressBar = "progress_bar"
    
    // MARK: - Error Handling
    
    static let errorView = "error_view"
    static let errorMessageLabel = "error_message_label"
    static let retryButton = "retry_button"
    
    // MARK: - Utility Methods
    
    /// Get accessibility identifier for a specific exercise
    static func exerciseCard(_ exerciseName: String) -> String {
        return "exercise_card_\(exerciseName.lowercased().replacingOccurrences(of: " ", with: "_"))"
    }
    
    /// Get accessibility identifier for a workout item
    static func workoutItem(_ workoutId: String) -> String {
        return "workout_item_\(workoutId)"
    }
    
    /// Get accessibility identifier for a set entry
    static func setEntry(_ exerciseName: String, setNumber: Int) -> String {
        return "set_entry_\(exerciseName.lowercased().replacingOccurrences(of: " ", with: "_"))_set_\(setNumber)"
    }
}