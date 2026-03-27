//
//  FoodLoggingViewModel.swift
//  AmakaFlow
//
//  ViewModel for AI food logging (AMA-1294).
//  Manages photo analysis, barcode lookup, and text parsing via chat-api.
//

import Foundation
import Combine
import SwiftUI

// MARK: - API Response Models

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

// MARK: - Food Logging Tab

enum FoodLoggingTab: String, CaseIterable {
    case photo = "Photo"
    case barcode = "Barcode"
    case text = "Text"

    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .barcode: return "barcode.viewfinder"
        case .text: return "text.alignleft"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class FoodLoggingViewModel: ObservableObject {

    // MARK: - Shared State

    @Published var selectedTab: FoodLoggingTab = .photo
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Photo Analysis State

    @Published var photoItems: [FoodItemResponse] = []
    @Published var photoTotals: MacroTotalsResponse?
    @Published var photoNotes: String?

    // MARK: - Barcode State

    @Published var barcodeResult: BarcodeNutritionAPIResponse?

    // MARK: - Text Parse State

    @Published var textItems: [FoodItemResponse] = []
    @Published var textTotals: MacroTotalsResponse?

    // MARK: - Reset

    func reset() {
        photoItems = []
        photoTotals = nil
        photoNotes = nil
        barcodeResult = nil
        textItems = []
        textTotals = nil
        errorMessage = nil
    }

    // MARK: - Analyze Photo

    func analyzePhoto(imageBase64: String) async {
        isLoading = true
        errorMessage = nil
        photoItems = []
        photoTotals = nil
        photoNotes = nil

        do {
            let response = try await postAnalyzePhoto(imageBase64: imageBase64)
            photoItems = response.items
            photoTotals = response.totals
            photoNotes = response.notes
        } catch {
            print("[FoodLoggingVM] analyzePhoto failed: \(error)")
            errorMessage = "Could not analyze photo. Please try again."
        }

        isLoading = false
    }

    // MARK: - Barcode Lookup

    func lookupBarcode(code: String) async {
        isLoading = true
        errorMessage = nil
        barcodeResult = nil

        do {
            let response = try await getBarcode(code: code)
            barcodeResult = response
        } catch let apiError as APIError {
            switch apiError {
            case .serverError(404):
                errorMessage = "Product not found. Try scanning again."
            case .serverError(400):
                errorMessage = "Invalid barcode format."
            default:
                errorMessage = "Barcode lookup failed. Please try again."
            }
        } catch {
            print("[FoodLoggingVM] lookupBarcode failed: \(error)")
            errorMessage = "Barcode lookup failed. Please try again."
        }

        isLoading = false
    }

    // MARK: - Parse Text

    func parseText(text: String) async {
        isLoading = true
        errorMessage = nil
        textItems = []
        textTotals = nil

        do {
            let response = try await postParseText(text: text)
            textItems = response.items
            textTotals = response.totals
        } catch {
            print("[FoodLoggingVM] parseText failed: \(error)")
            errorMessage = "Could not parse food description. Please try again."
        }

        isLoading = false
    }

    // MARK: - API Calls

    private func makeAuthenticatedRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        #if DEBUG
        if let testAuthSecret = TestAuthStore.shared.authSecret,
           let testUserId = TestAuthStore.shared.userId,
           !testAuthSecret.isEmpty {
            request.setValue(testAuthSecret, forHTTPHeaderField: "X-Test-Auth")
            request.setValue(testUserId, forHTTPHeaderField: "X-Test-User-Id")
        } else if let token = PairingService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #else
        if let token = PairingService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #endif

        return request
    }

    private func postAnalyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse {
        let baseURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(baseURL)/nutrition/analyze-photo") else {
            throw APIError.invalidResponse
        }

        let payload = ["image_base64": imageBase64]
        let body = try JSONEncoder().encode(payload)

        let request = makeAuthenticatedRequest(url: url, method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.serverError(statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AnalyzePhotoAPIResponse.self, from: data)
    }

    private func getBarcode(code: String) async throws -> BarcodeNutritionAPIResponse {
        let baseURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(baseURL)/nutrition/barcode/\(code)") else {
            throw APIError.invalidResponse
        }

        let request = makeAuthenticatedRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BarcodeNutritionAPIResponse.self, from: data)
    }

    private func postParseText(text: String) async throws -> ParseTextAPIResponse {
        let baseURL = AppEnvironment.current.chatAPIURL
        guard let url = URL(string: "\(baseURL)/nutrition/parse-text") else {
            throw APIError.invalidResponse
        }

        let payload = ["text": text]
        let body = try JSONEncoder().encode(payload)

        let request = makeAuthenticatedRequest(url: url, method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.serverError(statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ParseTextAPIResponse.self, from: data)
    }
}
