//
//  VolumeAnalyticsModels.swift
//  AmakaFlow
//
//  Models for volume analytics API responses (AMA-1414)
//

import Foundation

struct VolumeAnalyticsResponse: Codable {
    let data: [VolumeDataPoint]
    let summary: VolumeSummary
    let period: VolumePeriod
    let granularity: String
}

struct VolumeDataPoint: Codable, Identifiable {
    var id: String { "\(period)-\(muscleGroup)" }
    let period: String
    let muscleGroup: String
    let totalVolume: Double
    let totalSets: Int
    let totalReps: Int
}

struct VolumeSummary: Codable {
    let totalVolume: Double
    let totalSets: Int
    let totalReps: Int
    let muscleGroupBreakdown: [String: Double]
}

struct VolumePeriod: Codable {
    let startDate: String
    let endDate: String
}
