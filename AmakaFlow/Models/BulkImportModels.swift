//
//  BulkImportModels.swift
//  AmakaFlow
//
//  Models for bulk import API (AMA-1415)
//

import Foundation

// MARK: - Input Types

enum BulkInputType: String, CaseIterable {
    case urls
    case images
    case file

    var displayName: String {
        switch self {
        case .urls: return "URLs"
        case .images: return "Images"
        case .file: return "File"
        }
    }

    var icon: String {
        switch self {
        case .urls: return "link"
        case .images: return "photo"
        case .file: return "doc"
        }
    }
}

// MARK: - Detect

struct BulkDetectRequest: Codable {
    let profileId: String
    let sourceType: String
    let sources: [String]
}

struct BulkDetectResponse: Codable {
    let success: Bool
    let jobId: String
    let items: [DetectedItem]
    let total: Int
    let successCount: Int
    let errorCount: Int
}

struct DetectedItem: Codable, Identifiable {
    let id: String
    let sourceRef: String
    let parsedTitle: String?
    let parsedExerciseCount: Int?
    let confidence: Int
    let errors: [String]?
    let warnings: [String]?
}

// MARK: - Match

struct BulkMatchRequest: Codable {
    let jobId: String
    let profileId: String
    let userMappings: [String: String]?
}

struct BulkMatchResponse: Codable {
    let success: Bool
    let jobId: String
    let exercises: [ExerciseMatch]
    let totalExercises: Int
    let matched: Int
    let needsReview: Int
}

struct ExerciseMatch: Codable, Identifiable {
    let id: String
    let originalName: String
    let matchedGarminName: String?
    let confidence: Int
    let suggestions: [ExerciseSuggestion]?
    let status: String
    var userSelection: String?
}

struct ExerciseSuggestion: Codable {
    let name: String
    let confidence: Int
}

// MARK: - Preview

struct BulkPreviewRequest: Codable {
    let jobId: String
    let profileId: String
    let selectedIds: [String]
}

struct BulkPreviewResponse: Codable {
    let success: Bool
    let jobId: String
    let workouts: [PreviewWorkout]
    let stats: ImportStats
}

struct PreviewWorkout: Codable, Identifiable {
    let id: String
    let title: String
    let exerciseCount: Int
    let blockCount: Int?
    let validationIssues: [ValidationIssue]?
    var selected: Bool
    let isDuplicate: Bool
}

struct ValidationIssue: Codable, Identifiable {
    let id: String
    let severity: String  // error, warning, info
    let message: String
}

struct ImportStats: Codable {
    let totalDetected: Int
    let totalSelected: Int
    let exercisesMatched: Int
    let exercisesNeedingReview: Int
    let duplicatesFound: Int
    let validationErrors: Int
    let validationWarnings: Int
}

// MARK: - Execute

struct BulkExecuteRequest: Codable {
    let jobId: String
    let profileId: String
    let workoutIds: [String]
    let device: String
}

struct BulkExecuteResponse: Codable {
    let success: Bool
    let jobId: String
    let status: String
    let message: String
}

// MARK: - Status (polling)

struct BulkImportStatus: Codable {
    let success: Bool
    let jobId: String
    let status: String  // idle, running, complete, failed, cancelled
    let progress: Int
    let results: [ImportResult]?
    let error: String?
}

struct ImportResult: Codable, Identifiable {
    var id: String { workoutId }
    let workoutId: String
    let title: String
    let status: String  // success, failed, skipped
    let error: String?
    let savedWorkoutId: String?
}
