//
//  FoodLoggingViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for FoodLoggingViewModel (AMA-1294).
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class FoodLoggingViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() async {
        let vm = FoodLoggingViewModel()

        XCTAssertEqual(vm.selectedTab, .photo)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.photoItems.isEmpty)
        XCTAssertNil(vm.photoTotals)
        XCTAssertNil(vm.photoNotes)
        XCTAssertNil(vm.barcodeResult)
        XCTAssertTrue(vm.textItems.isEmpty)
        XCTAssertNil(vm.textTotals)
    }

    // MARK: - Reset

    func testResetClearsAllState() async {
        let vm = FoodLoggingViewModel()

        // Simulate some state
        vm.errorMessage = "Some error"
        vm.photoItems = [makeFoodItem(name: "Apple")]
        vm.photoTotals = makeTotals()
        vm.photoNotes = "Some notes"
        vm.textItems = [makeFoodItem(name: "Banana")]
        vm.textTotals = makeTotals()

        vm.reset()

        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.photoItems.isEmpty)
        XCTAssertNil(vm.photoTotals)
        XCTAssertNil(vm.photoNotes)
        XCTAssertNil(vm.barcodeResult)
        XCTAssertTrue(vm.textItems.isEmpty)
        XCTAssertNil(vm.textTotals)
    }

    // MARK: - Tab Enum

    func testFoodLoggingTabCases() {
        XCTAssertEqual(FoodLoggingTab.allCases.count, 3)
        XCTAssertEqual(FoodLoggingTab.photo.rawValue, "Photo")
        XCTAssertEqual(FoodLoggingTab.barcode.rawValue, "Barcode")
        XCTAssertEqual(FoodLoggingTab.text.rawValue, "Text")
    }

    func testFoodLoggingTabIcons() {
        XCTAssertEqual(FoodLoggingTab.photo.icon, "camera.fill")
        XCTAssertEqual(FoodLoggingTab.barcode.icon, "barcode.viewfinder")
        XCTAssertEqual(FoodLoggingTab.text.icon, "text.alignleft")
    }

    // MARK: - Response Model Decoding (uses explicit CodingKeys, no convertFromSnakeCase)

    func testFoodItemResponseDecoding() throws {
        let json = """
        {
            "name": "Grilled chicken",
            "calories": 284.0,
            "protein_g": 53.4,
            "carbs_g": 0.0,
            "fat_g": 6.2,
            "serving_size": "200g",
            "confidence": "high"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(FoodItemResponse.self, from: json)

        XCTAssertEqual(item.name, "Grilled chicken")
        XCTAssertEqual(item.calories, 284.0)
        XCTAssertEqual(item.proteinG, 53.4)
        XCTAssertEqual(item.carbsG, 0.0)
        XCTAssertEqual(item.fatG, 6.2)
        XCTAssertEqual(item.servingSize, "200g")
        XCTAssertEqual(item.confidence, "high")
    }

    func testFoodItemResponseDecodingWithoutOptionals() throws {
        let json = """
        {
            "name": "Apple",
            "calories": 95.0,
            "protein_g": 0.5,
            "carbs_g": 25.0,
            "fat_g": 0.3
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(FoodItemResponse.self, from: json)

        XCTAssertEqual(item.name, "Apple")
        XCTAssertNil(item.servingSize)
        XCTAssertNil(item.confidence)
    }

    func testBarcodeNutritionResponseDecoding() throws {
        let json = """
        {
            "barcode": "00100210001",
            "product_name": "Greek Yogurt",
            "brand": "Chobani",
            "serving_size": "170g",
            "calories": 100.0,
            "protein_g": 17.0,
            "carbs_g": 6.0,
            "fat_g": 0.7,
            "fiber_g": 0.0,
            "sugar_g": 4.0,
            "image_url": "https://example.com/image.jpg"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(BarcodeNutritionAPIResponse.self, from: json)

        XCTAssertEqual(result.barcode, "00100210001")
        XCTAssertEqual(result.productName, "Greek Yogurt")
        XCTAssertEqual(result.brand, "Chobani")
        XCTAssertEqual(result.proteinG, 17.0)
    }

    func testMacroTotalsResponseDecoding() throws {
        let json = """
        {
            "calories": 500.0,
            "protein_g": 58.4,
            "carbs_g": 44.8,
            "fat_g": 8.0
        }
        """.data(using: .utf8)!

        let totals = try JSONDecoder().decode(MacroTotalsResponse.self, from: json)

        XCTAssertEqual(totals.calories, 500.0)
        XCTAssertEqual(totals.proteinG, 58.4)
        XCTAssertEqual(totals.carbsG, 44.8)
        XCTAssertEqual(totals.fatG, 8.0)
    }

    func testParseTextResponseDecoding() throws {
        let json = """
        {
            "items": [
                {
                    "name": "Eggs",
                    "calories": 180.0,
                    "protein_g": 12.0,
                    "carbs_g": 1.0,
                    "fat_g": 14.0
                }
            ],
            "totals": {
                "calories": 180.0,
                "protein_g": 12.0,
                "carbs_g": 1.0,
                "fat_g": 14.0
            },
            "raw_text": "2 scrambled eggs"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ParseTextAPIResponse.self, from: json)

        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.rawText, "2 scrambled eggs")
        XCTAssertEqual(response.totals.proteinG, 12.0)
    }

    func testAnalyzePhotoResponseDecoding() throws {
        let json = """
        {
            "items": [
                {
                    "name": "Rice",
                    "calories": 216.0,
                    "protein_g": 5.0,
                    "carbs_g": 44.8,
                    "fat_g": 1.8,
                    "serving_size": "1 cup",
                    "confidence": "medium"
                }
            ],
            "totals": {
                "calories": 216.0,
                "protein_g": 5.0,
                "carbs_g": 44.8,
                "fat_g": 1.8
            },
            "notes": "Estimated from visual cues"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AnalyzePhotoAPIResponse.self, from: json)

        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.notes, "Estimated from visual cues")
        XCTAssertEqual(response.totals.calories, 216.0)
    }

    // MARK: - FoodItemResponse Identity

    func testFoodItemResponseIdentity() {
        let item = makeFoodItem(name: "Apple")
        XCTAssertEqual(item.id, "Apple")
    }

    // MARK: - Helpers

    private func makeFoodItem(name: String) -> FoodItemResponse {
        FoodItemResponse(
            name: name,
            calories: 100.0,
            proteinG: 5.0,
            carbsG: 20.0,
            fatG: 2.0,
            servingSize: nil,
            confidence: nil
        )
    }

    private func makeTotals() -> MacroTotalsResponse {
        MacroTotalsResponse(
            calories: 100.0,
            proteinG: 5.0,
            carbsG: 20.0,
            fatG: 2.0
        )
    }
}
