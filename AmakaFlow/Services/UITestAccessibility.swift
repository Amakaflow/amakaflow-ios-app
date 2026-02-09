//
//  UITestAccessibility.swift
//  AmakaFlow
//
//  Centralized accessibility identifiers for UITEST automation
//

import Foundation

/// Centralized accessibility identifiers for automation testing
struct UITestAccessibility {
    
    // MARK: - Main Navigation
    
    static let homeTab = "home_tab"
    static let workoutsTab = "workouts_tab"
    static let settingsTab = "settings_tab"
    static let calendarTab = "calendar_tab"
    
    // MARK: - Main Screens
    
    static let homeScreen = "home_screen"
    static let workoutsScreen = "workouts_screen"
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