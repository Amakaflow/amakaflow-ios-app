//
//  NutritionModels.swift
//  AmakaFlow
//
//  Shared nutrition API response models (AMA-1412).
//  Consolidated from FoodLoggingViewModel, FuelingViewModel, and ProteinNudgeService.
//

import Foundation

// MARK: - Food Logging Models

struct FoodItemResponse: Codable, Identifiable, Equatable {
    var id: String { name }

    let name: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let servingSize: String?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case name, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case servingSize = "serving_size"
        case confidence
    }
}

struct MacroTotalsResponse: Codable, Equatable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

struct AnalyzePhotoAPIResponse: Codable {
    let items: [FoodItemResponse]
    let totals: MacroTotalsResponse
    let notes: String?
}

struct BarcodeNutritionAPIResponse: Codable {
    let barcode: String
    let productName: String
    let brand: String?
    let servingSize: String?
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let sugarG: Double?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case barcode
        case productName = "product_name"
        case brand
        case servingSize = "serving_size"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case imageUrl = "image_url"
    }
}

struct ParseTextAPIResponse: Codable {
    let items: [FoodItemResponse]
    let totals: MacroTotalsResponse
    let rawText: String

    enum CodingKeys: String, CodingKey {
        case items, totals
        case rawText = "raw_text"
    }
}

// MARK: - Fueling Status Models

struct FuelingStatusResponse: Codable, Equatable {
    let status: String          // "green" | "yellow" | "red"
    let proteinPct: Double
    let caloriesPct: Double
    let hydrationPct: Double
    let message: String

    enum CodingKeys: String, CodingKey {
        case status
        case proteinPct = "protein_pct"
        case caloriesPct = "calories_pct"
        case hydrationPct = "hydration_pct"
        case message
    }
}

// MARK: - Protein Nudge Models

struct ProteinNudgeResponse: Codable, Equatable {
    let shouldNudge: Bool
    let proteinCurrent: Int
    let proteinTarget: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case shouldNudge = "should_nudge"
        case proteinCurrent = "protein_current"
        case proteinTarget = "protein_target"
        case message
    }
}
