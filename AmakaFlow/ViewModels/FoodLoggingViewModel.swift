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

    // MARK: - Dependencies

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

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
            let response = try await dependencies.apiService.analyzePhoto(imageBase64: imageBase64)
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
            let response = try await dependencies.apiService.lookupBarcode(code: code)
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
            let response = try await dependencies.apiService.parseText(text: text)
            textItems = response.items
            textTotals = response.totals
        } catch {
            print("[FoodLoggingVM] parseText failed: \(error)")
            errorMessage = "Could not parse food description. Please try again."
        }

        isLoading = false
    }

}
