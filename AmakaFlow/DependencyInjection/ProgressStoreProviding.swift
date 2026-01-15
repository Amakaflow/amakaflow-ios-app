//
//  ProgressStoreProviding.swift
//  AmakaFlow
//
//  Protocol abstraction for workout progress persistence to enable dependency injection and testing.
//

import Foundation

/// Protocol defining the workout progress storage interface for dependency injection
protocol ProgressStoreProviding {
    /// Save workout progress
    func save(_ progress: SavedWorkoutProgress)

    /// Load saved workout progress, if any
    func load() -> SavedWorkoutProgress?

    /// Clear saved workout progress
    func clear()
}

// MARK: - Live Implementation

/// Default implementation using UserDefaults (wraps SavedWorkoutProgress static methods)
class LiveProgressStore: ProgressStoreProviding {
    static let shared = LiveProgressStore()

    func save(_ progress: SavedWorkoutProgress) {
        progress.save()
    }

    func load() -> SavedWorkoutProgress? {
        SavedWorkoutProgress.load()
    }

    func clear() {
        SavedWorkoutProgress.clear()
    }
}
