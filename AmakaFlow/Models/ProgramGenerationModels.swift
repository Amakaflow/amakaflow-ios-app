//
//  ProgramGenerationModels.swift
//  AmakaFlow
//
//  Models for program generation API (AMA-1413)
//

import Foundation

struct ProgramGenerationRequest: Codable {
    let goal: String
    let experienceLevel: String
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let preferredDays: [Int]
    let timePerSession: Int
    let equipment: [String]
    let injuries: String?
    let focusAreas: [String]?
    let avoidExercises: [String]?
}

struct ProgramGenerationResponse: Codable {
    let jobId: String
    let status: String
    let programId: String?
    let error: String?
}

struct ProgramGenerationStatus: Codable {
    let jobId: String
    let status: String
    let progress: Int
    let programId: String?
    let error: String?
}
